import Foundation

public struct ItemModelsProducer
<Value, P: ResourceParams, E, ItemModelType: ItemModel, SectionModelType: SectionModel>
where ItemModelType.E == E {

    public typealias StateToListViewState =
        (ResourceState<Value, P, E>, ValueToListViewStateTransformer<Value, ItemModelType, SectionModelType>)
        -> ListViewState<ItemModelType, SectionModelType>

    private let stateToListViewState: StateToListViewState
    private let valueToListViewStateTransformer:
    ValueToListViewStateTransformer<Value, ItemModelType, SectionModelType>

    public init(
        stateToListViewState: @escaping StateToListViewState,
        valueToListViewStateTransformer:
            ValueToListViewStateTransformer<Value, ItemModelType, SectionModelType>
    ) {

        self.stateToListViewState = stateToListViewState
        self.valueToListViewStateTransformer = valueToListViewStateTransformer
    }

    public init(
        baseValueToListViewStateTransformer:
            ValueToListViewStateTransformer<Value, ItemModelType, SectionModelType>
    ) {

        self.stateToListViewState = { state, valueToListViewStateTransformer in
            if let value = state.value?.value {
                return valueToListViewStateTransformer.valueToListViewState(value)
            } else {
                return .notReady
            }
        }
        self.valueToListViewStateTransformer = baseValueToListViewStateTransformer
    }

    public static func withSingleSectionItems<P: ResourceParams>(
        _ singleSectionItems: @escaping (Value) -> [ItemModelType]
        ) -> ItemModelsProducer<Value, P, E, ItemModelType, NoSection> where ItemModelType.E == E {

        let valueToListViewStateTransformer =
            ValueToListViewStateTransformer<Value, ItemModelType, NoSection> { value in
                let section = SectionAndItems<ItemModelType, NoSection>(
                    NoSection(),
                    singleSectionItems(value)
                )
                return ListViewState<ItemModelType, NoSection>.readyToDisplay([section])
            }

        return ItemModelsProducer<Value, P, E, ItemModelType, NoSection>(
            baseValueToListViewStateTransformer: valueToListViewStateTransformer
        )
    }

    public func listViewState(with state: ResourceState<Value, P, E>)
        -> ListViewState<ItemModelType, SectionModelType> {

        return stateToListViewState(state, valueToListViewStateTransformer)
    }

    public func idiomatic(noResultsText: String)
        -> ItemModelsProducer<Value, P, E, IdiomaticItemModel<ItemModelType>, SectionModelType> {

            return ItemModelsProducer<Value, P, E, IdiomaticItemModel<ItemModelType>, SectionModelType>(
                stateToListViewState: { state, valueToIdiomaticListViewStateTransformer
                    -> ListViewState<IdiomaticItemModel<ItemModelType>, SectionModelType> in

                    return state.idiomaticListViewState(
                        valueToIdiomaticListViewStateTransformer: valueToIdiomaticListViewStateTransformer,
                        noResultsText: noResultsText
                    )
                },
                valueToListViewStateTransformer: valueToListViewStateTransformer.idiomatic()
            )
    }

}

public struct ValueToListViewStateTransformer
<Value, ItemModelType: ItemModel, SectionModelType: SectionModel> {

    public typealias ValueToListViewState = (Value) -> ListViewState<ItemModelType, SectionModelType>

    public let valueToListViewState: ValueToListViewState

    public init(_ valueToListViewState: @escaping ValueToListViewState) {
        self.valueToListViewState = valueToListViewState
    }

    public func idiomatic()
        -> ValueToListViewStateTransformer<Value, IdiomaticItemModel<ItemModelType>, SectionModelType> {

            return ValueToListViewStateTransformer
                <Value, IdiomaticItemModel<ItemModelType>, SectionModelType> { value
                -> ListViewState<IdiomaticItemModel<ItemModelType>, SectionModelType> in

                let innerListViewState = self.valueToListViewState(value)
                switch innerListViewState {
                case let .readyToDisplay(sectionsWithItems):
                    return .readyToDisplay(sectionsWithItems.map { sectionAndItems in
                        return SectionAndItems(
                            sectionAndItems.section,
                            sectionAndItems.items.map { IdiomaticItemModel.baseItem($0) }
                        )
                    })
                case .notReady:
                    return .notReady
                }
            }
    }
}