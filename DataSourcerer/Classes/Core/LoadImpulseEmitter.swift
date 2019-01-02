import Foundation

public protocol LoadImpulseEmitterProtocol: ObservableProtocol where ObservedValue == LoadImpulse<P> {
    associatedtype P: Parameters
    typealias LoadImpulsesOverTime = ValuesOverTime

    func emit(_ loadImpulse: LoadImpulse<P>)
}

public extension LoadImpulseEmitterProtocol {
    var any: AnyLoadImpulseEmitter<P> {
        return AnyLoadImpulseEmitter(self)
    }
}

public struct AnyLoadImpulseEmitter<P_: Parameters>: LoadImpulseEmitterProtocol {
    public typealias P = P_

    private let _observe: (@escaping LoadImpulsesOverTime) -> Disposable
    private let _emit: (LoadImpulse<P>) -> Void

    init<Emitter: LoadImpulseEmitterProtocol>(_ emitter: Emitter) where Emitter.P == P {
        self._emit = emitter.emit
        self._observe = emitter.observe
    }

    public func emit(_ loadImpulse: LoadImpulse<P_>) {
        _emit(loadImpulse)
    }

    public func observe(_ loadImpulsesOverTime: @escaping LoadImpulsesOverTime) -> Disposable {
        return _observe(loadImpulsesOverTime)
    }
}

public class DefaultLoadImpulseEmitter<P_: Parameters>: LoadImpulseEmitterProtocol, ObservableProtocol {
    public typealias P = P_
    public typealias LI = LoadImpulse<P>

    private let initialImpulse: LoadImpulse<P>?
    private let coreDatasource = SimpleDatasource<LI?>(nil)

    public init(initialImpulse: LoadImpulse<P>?) {
        self.initialImpulse = initialImpulse
    }

    public func observe(_ observe: @escaping LoadImpulsesOverTime) -> Disposable {

        if let initialImpulse = initialImpulse {
            observe(initialImpulse)
        }

        let innerDisposable = coreDatasource.observeWithoutCurrentValue { loadImpulse in
            if let loadImpulse = loadImpulse {
                observe(loadImpulse)
            }
        }
        let selfDisposable: Disposable = InstanceRetainingDisposable(self)
        return CompositeDisposable([innerDisposable, selfDisposable])
    }

    public func emit(_ loadImpulse: LoadImpulse<P>) {
        coreDatasource.emit(loadImpulse)
    }

}

public class RecurringLoadImpulseEmitter<P_: Parameters>: LoadImpulseEmitterProtocol, ObservableProtocol {
    public typealias P = P_
    public typealias LI = LoadImpulse<P>

    private let lastLoadImpulse: LoadImpulse<P>?
    private let innerEmitter: DefaultLoadImpulseEmitter<P>
    private let disposeBag = DisposeBag()
    private var timer = SynchronizedMutableProperty<DispatchSourceTimer?>(nil)
    private var isObserved = SynchronizedMutableProperty(false)
    private let timerExecuter = SynchronizedExecuter()
    private let timerEmitQueue: DispatchQueue

    // TODO: refactor to use SynchronizedMutableProperty
    public var timerMode: TimerMode {
        didSet {
            if let lastLoadImpulse = lastLoadImpulse {
                emit(lastLoadImpulse)
            }
            resetTimer()
        }
    }

    public init(initialImpulse: LoadImpulse<P>?,
                timerMode: TimerMode = .none,
                timerEmitQueue: DispatchQueue? = nil) {

        self.lastLoadImpulse = initialImpulse
        self.timerMode = timerMode
        self.innerEmitter = DefaultLoadImpulseEmitter<P>(initialImpulse: initialImpulse)
        self.timerEmitQueue = timerEmitQueue ??
            DispatchQueue(label: "datasourcerer.recurringloadimpulseemitter.timer", attributes: [])
    }

    private func resetTimer() {

        timer.modify { [weak self] timer in
            timer?.cancel()
            guard let self = self else { return }

            switch self.timerMode {
            case .none:
                break
            case let .timeInterval(timeInterval):
                let newTimer = DispatchSource.makeTimerSource(queue: self.timerEmitQueue)
                newTimer.schedule(deadline: .now() + timeInterval,
                                  repeating: timeInterval,
                                  leeway: .milliseconds(100))
                newTimer.setEventHandler { [weak self] in
                    guard let lastLoadImpulse = self?.lastLoadImpulse else { return }
                    self?.emit(lastLoadImpulse)
                }
                newTimer.resume()
                timer = newTimer
            }
        }
    }

    public func observe(_ observe: @escaping LoadImpulsesOverTime) -> Disposable {

        defer {
            if isObserved.set(true, ifCurrentValueIs: false) {
                resetTimer()
            }
        }

        let innerDisposable = innerEmitter.observe(observe)
        return CompositeDisposable(innerDisposable, objectToRetain: self)
    }

    public func emit(_ loadImpulse: LoadImpulse<P>) {
        innerEmitter.emit(loadImpulse)
        resetTimer()
    }

    deinit {
        disposeBag.dispose()
    }

    public enum TimerMode {
        case none
        case timeInterval(DispatchTimeInterval)
    }

}
