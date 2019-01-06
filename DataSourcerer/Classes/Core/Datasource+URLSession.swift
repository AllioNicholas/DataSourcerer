import Foundation

public extension Datasource {

    /// Loads data with the URLRequests produced by `URLRequestMaker`,
    /// whenever `loadImpulseEmitter` emits a load impulse. If
    /// any error is encountered, an error is sent instead, using
    /// `errorMaker`.
    init<Value, P: Parameters, E: StateError>(
        loadStatesWithURLRequest URLRequestMaker: @escaping (LoadImpulse<P>) throws -> URLRequest,
        errorMaker: @escaping (String) -> E,
        loadImpulseEmitter: AnyLoadImpulseEmitter<P>
        ) where ObservedValue == State<Value, P, E>, Value: Codable {

        typealias DatasourceState = ObservedValue

        self.init { sendState, disposable in

            disposable += loadImpulseEmitter.observe { loadImpulse in

                func sendError(_ error: E) {
                    sendState(DatasourceState.error(
                        error: error,
                        loadImpulse: loadImpulse,
                        fallbackValueBox: nil
                    ))
                }

                guard let urlRequest = try? URLRequestMaker(loadImpulse) else {
                    sendError(errorMaker("Request could not be generated"))
                    return
                }

                let config = URLSessionConfiguration.default
                let session = URLSession(configuration: config)

                let task = session.dataTask(with: urlRequest) { data, _, error in

                    guard error == nil else {
                        sendError(errorMaker("""
                        Request could not be loaded -
                        we are too lazy to parse the actual error yet ;)
                        """))
                        return
                    }

                    // make sure we got data
                    guard let responseData = data else {
                        sendError(errorMaker("responseData is nil"))
                        return
                    }

                    do {
                        let value = try JSONDecoder.decode(responseData,
                                                           to: Value.self)
                        let state = DatasourceState.value(valueBox: EquatableBox(value),
                                                          loadImpulse: loadImpulse,
                                                          fallbackError: nil)
                        sendState(state)
                    } catch {
                        sendError(errorMaker("""
                            Value cannot be parsed: \(String(describing: error))
                            """))
                        return
                    }
                }
                task.resume()

                disposable += ActionDisposable { [weak task] in
                    task?.cancel()
                }
            }
        }
    }
}