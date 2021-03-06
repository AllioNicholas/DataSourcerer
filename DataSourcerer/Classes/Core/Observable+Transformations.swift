import Foundation

public extension ObservableProtocol {

    func map<TransformedValue>(_ transform: @escaping (ObservedValue) -> (TransformedValue))
        -> AnyObservable<TransformedValue> {

            return ValueStream<TransformedValue> { sendValue, disposable in
                disposable += self.observe { value in
                    sendValue(transform(value))
                }
            }.any
    }

    /// Acts like RxSwift's flatMapLatest or ReactiveSwift's flatMap(.latest):
    func flatMapLatest<TransformedValue>(
        _ transform: @escaping (ObservedValue) -> (AnyObservable<TransformedValue>)
    ) -> AnyObservable<TransformedValue> {

        var latestInnerDisposable: Disposable?

        return ValueStream<TransformedValue> { sendValue, disposable in

            disposable += self.observe { nextValue in

                latestInnerDisposable?.dispose()

                let nextObservable = transform(nextValue)
                let nextInnerDisposable = nextObservable.observe { transformedValue in
                    sendValue(transformedValue)
                }
                latestInnerDisposable = nextInnerDisposable
                disposable += nextInnerDisposable
            }
        }.any
    }

    func reduce<ReducedValue>(_ reduce:
        @escaping (_ previous: ReducedValue?, _ next: ObservedValue) -> (ReducedValue))
        -> AnyObservable<ReducedValue> {

            return ValueStream<ReducedValue> { sendValue, disposable in

                let cumulativeValue = SynchronizedMutableProperty<ReducedValue?>(nil)

                disposable += self.observe { value in
                    let next = reduce(cumulativeValue.value, value)
                    cumulativeValue.value = next
                    sendValue(next)
                }
            }.any
    }

    public func startWith(value: ObservedValue) -> AnyObservable<ObservedValue> {

        return ValueStream<ObservedValue> { sendValue, disposable in

            sendValue(value)

            disposable += self.observe { value in
                sendValue(value)
            }
        }.any
    }

    /// Very similar to combineLatest() in ReactiveSwift
    static func combine<S: Sequence, CombinedValue>(
        observables: S,
        map: @escaping ([ObservedValue]) -> (CombinedValue)
    ) -> AnyObservable<CombinedValue> where S.Element == AnyObservable<ObservedValue> {

        return ValueStream<CombinedValue> { sendValue, disposable in

            let executer = SynchronizedExecuter()
            let observablesArray = Array(observables)
            let receivedValues = observablesArray.map { _ in SynchronizedMutableProperty<ObservedValue?>(nil) }

            // unsynchronized!
            func sendIfAllValuesExist() {
                let values = receivedValues.compactMap { $0.value }
                guard values.count == observablesArray.count else { return }
                sendValue(map(values))
            }

            for (index, observable) in observables.enumerated() {
                disposable += observable.observe { value in
                    executer.sync {
                        receivedValues[index].value = value
                        sendIfAllValuesExist()
                    }
                }
            }

        }.any
    }

    /// Very similar to combineLatest(with:) in ReactiveSwift
    func combine<OtherValue>(with other: AnyObservable<OtherValue>)
        -> AnyObservable<(ObservedValue, OtherValue)> {

        return ValueStream<(ObservedValue, OtherValue)> { sendValue, disposable in

            let values = SynchronizedMutableProperty<(ObservedValue?, OtherValue?)>((nil, nil))
            let executer = SynchronizedExecuter()

            // unsynchronized!
            func sendIfAllValuesExist() {
                guard let selfValue = values.value.0, let otherValue = values.value.1 else {
                    return
                }

                sendValue((selfValue, otherValue))
            }

            disposable += other.observe { value in
                executer.sync {
                    var newValues = values.value
                    newValues.1 = value
                    values.value = newValues
                    sendIfAllValuesExist()
                }
            }

            disposable += self.observe { value in
                executer.sync {
                    var newValues = values.value
                    newValues.0 = value
                    values.value = newValues
                    sendIfAllValuesExist()
                }
            }

        }.any
    }

    func filter(_ include: @escaping (ObservedValue) -> (Bool))
        -> AnyObservable<ObservedValue> {

            return ValueStream { sendValue, disposable in
                disposable += self.observe { value in
                    if include(value) {
                        sendValue(value)
                    }
                }
            }.any
    }

    func observe(on queue: DispatchQueue) -> AnyObservable<ObservedValue> {
        return observe(on: queue, if: { _ in true })
    }

    func observe(on queue: DispatchQueue,
                 if: @escaping (ObservedValue) -> Bool) -> AnyObservable<ObservedValue> {

        return ValueStream<ObservedValue> { sendValue, disposable in
            disposable += self.observe { value in
                if `if`(value) {
                    queue.async {
                        sendValue(value)
                    }
                } else {
                    sendValue(value)
                }
            }
        }.any
    }

    func observeOnUIThread() -> AnyObservable<ObservedValue> {

        let core = UIDatasourceCore<ObservedValue>()

        return ValueStream<ObservedValue> { sendValue, disposable in
            disposable += self.observe { value in
                core.emitNext(value: value, sendValue: sendValue)
            }
        }.any
    }

    func skipRepeats(_ isEqual: @escaping (_ lhs: ObservedValue, _ rhs: ObservedValue) -> Bool)
        -> AnyObservable<ObservedValue> {

            let core = SkipRepeatsCore(isEqual)

            return ValueStream<ObservedValue> { sendValue, disposable in
                disposable += self.observe { value in
                    core.emitNext(value: value, sendValue: sendValue)
                }
            }.any
    }

    func skip(first count: Int) -> AnyObservable<ObservedValue> {
        guard count > 0 else { return self.any }

        return ValueStream { sendValue, disposable in
            var skipped = 0
            disposable += self.observe { value in
                if skipped < count {
                    skipped += 1
                } else {
                    sendValue(value)
                }
            }
        }.any
    }

}

public extension ObservableProtocol where ObservedValue: Equatable {

    func skipRepeats() -> AnyObservable<ObservedValue> {
        return skipRepeats({ $0 == $1 })
    }

}

internal struct UIDatasourceQueueInitializer {
    internal static let dispatchSpecificKey = DispatchSpecificKey<UInt8>()
    internal static let dispatchSpecificValue = UInt8.max

    static var initializeOnce: () = {
        DispatchQueue.main.setSpecific(key: dispatchSpecificKey,
                                       value: dispatchSpecificValue)
    }()
}

/// Heavily inspired by UIScheduler from ReactiveSwift.
public final class UIDatasourceCore<Value> {

    // `inout` references do not guarantee atomicity. Use `UnsafeMutablePointer`
    // instead.
    //
    // https://lists.swift.org/pipermail/swift-users/Week-of-Mon-20161205/004147.html
    private let queueLength: UnsafeMutablePointer<Int32> = {
        let memory = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        memory.initialize(to: 0)
        return memory
    }()

    deinit {
        queueLength.deinitialize(count: 1)
        queueLength.deallocate()
    }

    /// Initializes `UIDatasource`
    public init() {
        /// This call is to ensure the main queue has been setup appropriately
        /// for `UIDatasource`. It is only called once during the application
        /// lifetime, since Swift has a `dispatch_once` like mechanism to
        /// lazily initialize global variables and static variables.
        _ = UIDatasourceQueueInitializer.initializeOnce
    }

    public func emitNext(value: Value, sendValue: @escaping (Value) -> Void) {

        let positionInQueue = self.enqueue()

        // If we're already running on the main queue, and there isn't work
        // already enqueued, we can skip scheduling and just execute directly.
        if positionInQueue == 1 && DispatchQueue.getSpecific(
            key: UIDatasourceQueueInitializer.dispatchSpecificKey) ==
            UIDatasourceQueueInitializer.dispatchSpecificValue {
            sendValue(value)
            self.dequeue()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                sendValue(value)
                self.dequeue()
            }
        }
    }

    private func dequeue() {
        OSAtomicDecrement32(queueLength)
    }

    private func enqueue() -> Int32 {
        return OSAtomicIncrement32(queueLength)
    }

}

public final class SkipRepeatsCore<Value> {

    private let lastValue: SynchronizedMutableProperty<Value?>
    private let isEqual: (Value, Value) -> (Bool)

    public init(_ isEqual: @escaping (Value, Value) -> (Bool)) {
        self.isEqual = isEqual
        self.lastValue = SynchronizedMutableProperty(nil)
    }

    public func emitNext(value: Value, sendValue: (Value) -> Void) {

        let changed: Bool = {
            guard let lastValue = self.lastValue.value else {
                return true
            }
            return self.isEqual(value, lastValue) == false
        }()

        guard changed else { return }

        lastValue.value = value
        sendValue(value)
    }

}
