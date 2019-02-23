import Foundation

// Holds closures of essential list view callbacks (mostly a minimal intersection
// of UITableViewDatasource and UICollectionViewDatasource).
//
// If you think a closure is missing (and you can therefore not use this struct
// for your own purposes), please create an issue at the Github page.
public struct ListViewDatasourceCore
    <ObservedValue, Item: ListItem, ItemView: UIView, Section: ListSection,
    HeaderItem: SupplementaryItem, HeaderItemView: UIView,
    FooterItem: SupplementaryItem, FooterItemView: UIView,
    ContainingView: UIView> {
    public typealias ItemViewAdapter = ListViewItemAdapter<Item, ItemView, ContainingView>
    public typealias HeaderItemViewAdapter = ListViewItemAdapter<HeaderItem, HeaderItemView, ContainingView>
    public typealias FooterItemViewAdapter = ListViewItemAdapter<FooterItem, FooterItemView, ContainingView>
    public typealias ValueToSections = (ObservedValue) -> ListSections<Item, Section>

    // MARK: - Definitions based on UITableViewDatasource & UICollectionViewDatasource
    public typealias HeaderItemAtIndexPath = (IndexPath) -> HeaderItem?
    public typealias FooterItemAtIndexPath = (IndexPath) -> FooterItem?
    public typealias TitleForHeaderInSection = (Int) -> String?
    public typealias TitleForFooterInSection = (Int) -> String?
    public typealias IndexTitles = () -> [String]?
    public typealias IndexPathForIndexTitle = (_ title: String, _ index: Int) -> IndexPath

    // MARK: - Definitions based on UITableViewDelegate & UICollectionViewDelegate
    public typealias WillDisplayItem = (ItemView, Item, IndexPath) -> Void
    public typealias WillDisplayHeaderItem =
        (HeaderItemView, HeaderItem, IndexPath) -> Void
    public typealias WillDisplayFooterItem =
        (FooterItemView, FooterItem, IndexPath) -> Void

    public let valueProperty: ObservableProperty<ObservedValue>
    public let sectionsProperty: ObservableProperty<ListSections<Item, Section>>
    public let valueToSections: ValueToSections
    public let itemViewAdapter: ItemViewAdapter
    public let headerItemViewAdapter: HeaderItemViewAdapter
    public let footerItemViewAdapter: FooterItemViewAdapter

    // MARK: - Vars based on UITableViewDatasource & UICollectionViewDatasource
    public var headerItemAtIndexPath: HeaderItemAtIndexPath?
    public var footerItemAtIndexPath: FooterItemAtIndexPath?
    public var titleForHeaderInSection: TitleForHeaderInSection?
    public var titleForFooterInSection: TitleForFooterInSection?
    public var sectionIndexTitles: IndexTitles?
    public var indexPathForIndexTitle: IndexPathForIndexTitle?

    // MARK: - Vars based on UITableViewDelegate & UICollectionViewDelegate
    public var willDisplayItem: WillDisplayItem?
    public var willDisplayHeaderItem: WillDisplayHeaderItem?
    public var willDisplayFooterItem: WillDisplayFooterItem?

    public init(valueProperty: ObservableProperty<ObservedValue>,
                valueToSections: @escaping ValueToSections,
                itemViewAdapter: ItemViewAdapter,
                headerItemViewAdapter: HeaderItemViewAdapter,
                footerItemViewAdapter: FooterItemViewAdapter,
                headerItemAtIndexPath: HeaderItemAtIndexPath?,
                footerItemAtIndexPath: FooterItemAtIndexPath?,
                titleForHeaderInSection: TitleForHeaderInSection?,
                titleForFooterInSection: TitleForFooterInSection?,
                sectionIndexTitles: IndexTitles?,
                indexPathForIndexTitle: IndexPathForIndexTitle?,
                willDisplayItem: WillDisplayItem?,
                willDisplayHeaderItem: WillDisplayHeaderItem?,
                willDisplayFooterItem: WillDisplayFooterItem?) {

        self.valueProperty = valueProperty
        self.valueToSections = valueToSections
        self.itemViewAdapter = itemViewAdapter
        self.headerItemViewAdapter = headerItemViewAdapter
        self.footerItemViewAdapter = footerItemViewAdapter
        self.headerItemAtIndexPath = headerItemAtIndexPath
        self.footerItemAtIndexPath = footerItemAtIndexPath
        self.titleForHeaderInSection = titleForHeaderInSection
        self.titleForFooterInSection = titleForFooterInSection
        self.sectionIndexTitles = sectionIndexTitles
        self.indexPathForIndexTitle = indexPathForIndexTitle
        self.willDisplayItem = willDisplayItem
        self.willDisplayHeaderItem = willDisplayHeaderItem
        self.willDisplayFooterItem = willDisplayFooterItem

        self.sectionsProperty = valueProperty
            .map { valueToSections($0) }
            .observeOnUIThread()
            .property(initialValue: .notReady)
    }

    public init(simpleCoreWithValueProperty valueProperty: ObservableProperty<ObservedValue>,
                valueToSections: @escaping ValueToSections,
                itemViewAdapter: ItemViewAdapter,
                headerItemViewAdapter: HeaderItemViewAdapter,
                footerItemViewAdapter: FooterItemViewAdapter) {

        self.init(valueProperty: valueProperty,
                  valueToSections: valueToSections,
                  itemViewAdapter: itemViewAdapter,
                  headerItemViewAdapter: headerItemViewAdapter,
                  footerItemViewAdapter: footerItemViewAdapter,
                  headerItemAtIndexPath: nil,
                  footerItemAtIndexPath: nil,
                  titleForHeaderInSection: nil,
                  titleForFooterInSection: nil,
                  sectionIndexTitles: nil,
                  indexPathForIndexTitle: nil,
                  willDisplayItem: nil,
                  willDisplayHeaderItem: nil,
                  willDisplayFooterItem: nil)
    }

}

public extension ListViewDatasourceCore {

    var sections: ListSections<Item, Section> {
        return sectionsProperty.value
    }

    func section(at index: Int) -> SectionWithItems<Item, Section> {
        let rawSection = sections.sectionedValues.sectionsAndValues[index]
        return SectionWithItems(rawSection.0, rawSection.1)
    }

    func item(at indexPath: IndexPath) -> Item {
        return items(in: indexPath.section)[indexPath.row]
    }

    func items(in section: Int) -> [Item] {
        return valueToSections(valueProperty.value).sectionedValues.sectionsAndValues[section].1
    }

    func itemView(at indexPath: IndexPath, in containingView: ContainingView) -> ItemView {
        return itemViewAdapter.produceView(item(at: indexPath), containingView, indexPath)
    }

    func headerView(at indexPath: IndexPath,
                    in containingView: ContainingView) -> HeaderItemView? {
        guard let item = headerItemAtIndexPath?(indexPath) else {
            return nil
        }

        return headerItemViewAdapter.produceView(item, containingView, indexPath)
    }

    func footerView(at indexPath: IndexPath,
                    in containingView: ContainingView) -> FooterItemView? {
        guard let item = footerItemAtIndexPath?(indexPath) else {
            return nil
        }

        return footerItemViewAdapter.produceView(item, containingView, indexPath)
    }

    func headerSize(at indexPath: IndexPath,
                    in containingView: ContainingView) -> CGSize {
        guard let item = headerItemAtIndexPath?(indexPath) else {
            return .zero
        }

        return headerItemViewAdapter.itemViewSize?(item, containingView) ?? .zero
    }

    func footerSize(at indexPath: IndexPath,
                    in containingView: ContainingView) -> CGSize {
        guard let item = footerItemAtIndexPath?(indexPath) else {
            return .zero
        }

        return footerItemViewAdapter.itemViewSize?(item, containingView) ?? .zero
    }

}

public extension ListViewDatasourceCore {

    func idiomatic<Value, P: Parameters, E: StateError, ViewProducer: ListItemViewProducer>(
        noResultsText: String,
        loadingViewProducer: ViewProducer,
        errorViewProducer: ViewProducer,
        noResultsViewProducer: ViewProducer
        )
        -> ListViewDatasourceCore<ObservedValue, IdiomaticListItem<Item>, ItemView, Section,
        HeaderItem, HeaderItemView, FooterItem, FooterItemView, ContainingView>
        where ObservedValue == State<Value, P, E>,
        ViewProducer.Item == IdiomaticListItem<Item>, ViewProducer.ProducedView == ItemView,
        ViewProducer.ContainingView == ContainingView, Item.E == E {

            typealias IdiomaticItem = IdiomaticListItem<Item>
            typealias IdiomaticSections = ListSections<IdiomaticItem, Section>

            let originalValueToSections = self.valueToSections
            let valueToSections = { (state: ObservedValue) -> IdiomaticSections in
                let sections = originalValueToSections(state)
                let idiomaticSections = sections.sectionsWithItems?
                    .map { sectionWithItems -> SectionWithItems<IdiomaticItem, Section> in
                        let items = sectionWithItems.items
                            .map { IdiomaticListItem.datasourceItem($0) }
                        return SectionWithItems(sectionWithItems.section, items)
                    }
                return IdiomaticSections.readyToDisplay(idiomaticSections ?? [])
            }

            let idiomaticItemViewAdapter = self.itemViewAdapter.idiomatic(
                loadingViewProducer: loadingViewProducer,
                errorViewProducer: errorViewProducer,
                noResultsViewProducer: noResultsViewProducer
            )

            return ListViewDatasourceCore
                <ObservedValue, IdiomaticListItem<Item>, ItemView,
                Section, HeaderItem, HeaderItemView, FooterItem, FooterItemView,
                ContainingView> (
                    valueProperty: valueProperty,
                    valueToSections: valueToSections,
                    itemViewAdapter: idiomaticItemViewAdapter,
                    headerItemViewAdapter: headerItemViewAdapter,
                    footerItemViewAdapter: footerItemViewAdapter,
                    headerItemAtIndexPath: headerItemAtIndexPath,
                    footerItemAtIndexPath: footerItemAtIndexPath,
                    titleForHeaderInSection: titleForHeaderInSection,
                    titleForFooterInSection: titleForFooterInSection,
                    sectionIndexTitles: sectionIndexTitles,
                    indexPathForIndexTitle: indexPathForIndexTitle,
                    willDisplayItem: { itemView, item, indexPath in
                        switch item {
                        case let .datasourceItem(datasourceItem):
                            self.willDisplayItem?(itemView, datasourceItem, indexPath)
                        case .loading, .error, .noResults:
                            break
                        }
                    },
                    willDisplayHeaderItem: willDisplayHeaderItem,
                    willDisplayFooterItem: willDisplayFooterItem
            )
    }
}

public typealias TableViewDatasourceCore
    <ObservedValue, Cell: ListItem, CellView: UITableViewCell,
    Section: ListSection, HeaderItem: SupplementaryItem, HeaderItemView: UIView,
    FooterItem: SupplementaryItem, FooterItemView: UIView>
    =
    ListViewDatasourceCore
    <ObservedValue, Cell, CellView, Section, HeaderItem, HeaderItemView,
    FooterItem, FooterItemView, UITableView>