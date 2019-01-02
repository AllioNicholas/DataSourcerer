import Foundation

/// Repeats a datasource's last value and/or error, mixed into
/// the latest returned state. E.g. if the original datasource
/// has sent a state with a value and provisioningState == .result,
/// then value is attached to subsequent states as `fallbackValue`
/// until a new state with a value and provisioningState == .result
/// is sent. Same with errors.
///
/// Discussion: A list view is not only interested in the very last
/// state of a datasource, but also in previous ones. E.g. on
/// pull-to-refresh, the original datasource might decide to emit
/// a loading state without a value - which would result in the
/// list view showing an empty view, or a loading view until the
/// next state with a value is sent (same with errors).
/// This struct helps with this by caching the last value and/or
/// error,.
open class LastResultRetainingDatasource
<Value_: Any, P_: Parameters, E_: DatasourceError>: StateDatasourceProtocol {

    public typealias Value = Value_
    public typealias P = P_
    public typealias E = E_
    public typealias SourceDatasource = AnyDatasource<State<Value, P, E>>

    public var currentValue: SynchronizedProperty<DatasourceState> {
        return coreDatasource.currentValue
    }

    private let sourceDatasource: SourceDatasource
    private let coreDatasource = SimpleDatasource<State<Value, P, E>>(.notReady)
    private let lastResult = SynchronizedMutableProperty<LastResult?>(nil)
    private var isObserved = SynchronizedMutableProperty<Bool>(false)

    public init(sourceDatasource: SourceDatasource) {
        self.sourceDatasource = sourceDatasource
    }

    public func observe(_ statesOverTime: @escaping StatesOverTime) -> Disposable {

        let innerDisposable = coreDatasource.observe(statesOverTime)
        let compositeDisposable = CompositeDisposable(innerDisposable, objectToRetain: self)

        if isObserved.set(true, ifCurrentValueIs: false) {
            compositeDisposable.add(startObserving())
        }

        return compositeDisposable
    }

    private func startObserving() -> Disposable {

        return sourceDatasource.observe { [weak self] state in
            guard let self = self else { return }

            defer {
                // Set lastResult if a matching value or error is contained
                // in state.
                switch state.provisioningState {
                case .loading, .notReady:
                    break
                case .result:
                    guard let loadImpulse = state.loadImpulse else {
                        break
                    }

                    if self.value(innerState: state, loadImpulse: loadImpulse) != nil {
                        self.lastResult.value = .value(state)
                    } else if self.error(innerState: state, loadImpulse: loadImpulse) != nil {
                        self.lastResult.value = .error(state)
                    }
                }
            }

            let nextState = self.nextState(innerState: state)
            self.coreDatasource.emit(nextState)
        }
    }

    private func nextState(innerState: DatasourceState) -> DatasourceState {
        switch innerState.provisioningState {
        case .notReady:
            return DatasourceState.notReady
        case .loading:
            guard let loadImpulse = innerState.loadImpulse else { return .notReady }

            let valueBox = self.value(innerState: innerState, loadImpulse: loadImpulse)
            let error = self.error(innerState: innerState, loadImpulse: loadImpulse)
            return DatasourceState.loading(loadImpulse: loadImpulse,
                                           fallbackValueBox: valueBox,
                                           fallbackError: error)
        case .result:
            guard let loadImpulse = innerState.loadImpulse else { return .notReady }

            if let error = innerState.cacheCompatibleError(for: loadImpulse) {
                let valueBox = self.value(innerState: innerState, loadImpulse: loadImpulse)
                return DatasourceState.error(error: error,
                                             loadImpulse: loadImpulse,
                                             fallbackValueBox: valueBox)
            } else if let valueBox = innerState.cacheCompatibleValue(for: loadImpulse) {
                // We have a definitive success result, with no error, so we erase all previous errors
                return DatasourceState.value(valueBox: valueBox,
                                             loadImpulse: loadImpulse,
                                             fallbackError: nil)
            } else {
                // Latest state might not match current parameters - return .notReady
                // so all cached data is purged. This can happen if e.g. an authenticated API
                // request has been made, but the user has logged out in the meantime. The result
                // must be discarded or the next logged in user might see the previous user's data.
                return DatasourceState.notReady
            }
        }
    }

    /// Returns either the current state's value, or the fallbackValueState's.
    /// If neither is set, returns nil.
    private func value(innerState: DatasourceState,
                       loadImpulse: LoadImpulse<P>) -> EquatableBox<Value>? {

        if let innerStateValueBox = innerState.cacheCompatibleValue(for: loadImpulse) {
            return innerStateValueBox
        } else if let fallbackValueStateValueBox =
            lastResult.value?.valueState?.cacheCompatibleValue(for: loadImpulse) {
            return fallbackValueStateValueBox
        } else {
            return nil
        }
    }

    /// Returns either the current state's error, or the fallbackErrorState's.
    /// If neither is set, returns nil.
    private func error(innerState: DatasourceState,
                       loadImpulse: LoadImpulse<P>) -> E? {

        if let innerStateError = innerState.cacheCompatibleError(for: loadImpulse) {
            return innerStateError
        } else if let fallbackError = lastResult.value?.errorState?.cacheCompatibleError(for: loadImpulse) {
            return fallbackError
        } else {
            return nil
        }
    }

    public enum LastResult {
        case value(DatasourceState)
        case error(DatasourceState)

        var valueState: DatasourceState? {
            switch self {
            case let .value(value) where value.value != nil: return value
            default: return nil
            }
        }

        var errorState: DatasourceState? {
            switch self {
            case let .error(error) where error.error != nil: return error
            default: return nil
            }
        }
    }

}

public extension DatasourceProtocol {

    func retainLastResult<Value, P: Parameters, E: DatasourceError>()
        -> LastResultRetainingDatasource<Value, P, E> where ObservedValue == State<Value, P, E> {
            return LastResultRetainingDatasource(sourceDatasource: self.any)
    }
}
