{CompositeDisposable} = require 'atom'

module.exports =

  activate: ->
    ## We want to execute as soon as 'tabs' and 'pinned-tabs' have activated
    onDidActivatePackages ['tabs', 'pinned-tabs'], =>
      # pinned-tabs is delaying it's activation, so wait longer than it
      setTimeout =>
        @activateAfterTabBar()
      , 5
    return

  activateAfterTabBar: ->
    ## Latch on center pane's tab bar
    atomTabs = atom.packages.getLoadedPackage('tabs').mainModule
    @tabBar = atomTabs.tabBarViews
      .filter((tabBar) => tabBar.location is 'center')[0]

    # I could easily get the pane from atom.workspace.getPanes()
    # but I need the tabBar for monkey-patching
    pane = @tabBar.pane

    # Another way to get the element would be to get the first child of the pane
    @element = @tabBar.element

    @pinnedTabs = atom.packages.getLoadedPackage('pinned-tabs')?.mainModule

    ## Subscribe to events, letting @tabBar to react first
    @subscriptions = new CompositeDisposable

    @subscriptions.add pane.onDidAddItem ({item, index}) =>
      @recalculateLayout()

    @subscriptions.add pane.onDidMoveItem ({item, newIndex}) =>
      @recalculateLayout()
      # Pinned tabs animate the pinned tab's width
      if @pinnedTabs?
        setTimeout =>
          @recalculateLayout()
        , 300

    @subscriptions.add pane.onDidRemoveItem ({item}) =>
      @recalculateLayout()

    @subscriptions.add pane.onDidChangeFlexScale =>
      window.requestAnimationFrame =>
        @recalculateLayout()

    @subscriptions.add atom.themes.onDidChangeActiveThemes =>
      @recalculateLayoutBasedOnTheme()

    @onDragOver = @onDragOver.bind(this)
    @onMouseWheel = @onMouseWheel.bind(this)
    @element.addEventListener 'dragover', @onDragOver
    @element.addEventListener 'mousewheel', @onMouseWheel

    # TODO: no way to observe closing of side docks :(

    @recalculateLayoutOnResize = @recalculateLayoutOnResize.bind(this)

    # Used to react to side docks resizing
    window.addEventListener 'mouseup', @recalculateLayoutOnResize

    # Normal window resizing
    window.addEventListener 'resize', @recalculateLayoutOnResize

    ## Monkey patch the tab bar
    # I use monkey-patching because I need to prevent the `scrollIntoView`
    # in the original implementation
    stackedTabs = @
    setActiveTab = (tabView) ->
      if tabView? and tabView isnt @activeTab
        @activeTab?.element.classList.remove('active')
        @activeTab = tabView
        @activeTab.element.classList.add('active')

        # @activeTab.element.scrollIntoView(false)
        window.requestAnimationFrame =>
          stackedTabs.recalculateLayoutToShow @activeTab.element

    @originalSetActiveTab = @tabBar.setActiveTab
    @tabBar.setActiveTab = setActiveTab.bind(@tabBar)

    ## Initialize state
    @scrollPos = @element.scrollLeft
    @element.classList.add('stacked-tab-bar')

    ## Kicks off first layout
    @recalculateLayoutBasedOnTheme()
    return

  recalculateLayoutBasedOnTheme: ->
    # Theme related state
    window.requestAnimationFrame =>
      @tabMargin = null
      tabBarStyle = window.getComputedStyle @element
      @paddingLeft = parseInt tabBarStyle.paddingLeft
      paddingRight = parseInt tabBarStyle.paddingRight
      @padding = @paddingLeft + paddingRight
      @recalculateLayout()
    return

  deactivate: ->
    ## Kill subscriptions
    @subscriptions.dispose()
    window.requestAnimationFrame =>
      @resetLayout()
    @element.removeEventListener 'mousewheel', @onMouseWheel
    @element.removeEventListener 'dragover', @onDragOver
    window.removeEventListener 'mouseup', @recalculateLayoutOnResize
    window.removeEventListener 'resize', @recalculateLayoutOnResize

    ## Monkey-unpatch
    @tabBar.setActiveTab = @originalSetActiveTab.bind(@tabBar)


  onMouseWheel: (event) ->
    @recalculateLayout event.wheelDeltaX
    return

  onDragOver: ->
    @recalculateLayout()
    return

  # Trying to keep this as fast as possible, avoiding memory allocation
  # and object field accesses
  recalculateLayout: (deltaX = 0) ->
    tabs = @element.children
    if tabs.length is 0
      return

    # Get tab margin from first tab and cache it for this theme
    if !@tabMargin?
      tabStyle = window.getComputedStyle @element.children[0]
      @tabMargin = parseInt(tabStyle.marginLeft) +
        parseInt(tabStyle.marginRight)

    normalTabsWidth = 0
    numNormalTabs = 0
    pinnedTabsWidth = 0
    maybePinned = @pinnedTabs?
    for tab in tabs
      if maybePinned and @pinnedTabs.isPinned tab
        pinnedTabsWidth += tab.clientWidth + @tabMargin
      else
        maybePinned = no
        numNormalTabs++
        normalTabsWidth += tab.clientWidth + @tabMargin

    totalWidth = @element.clientWidth
    availableWidthForNormalTabs = totalWidth - @padding - pinnedTabsWidth

    @scrollPos = bounded 0, normalTabsWidth - availableWidthForNormalTabs,
      @scrollPos - deltaX

    at = 0
    zIndex = numNormalTabs
    activeTabZIndexOffset = 1
    # using tabBar as optimization over classList
    activeTab = @tabBar.activeTab?.element
    normalTabs = 0
    maybePinned = @pinnedTabs?
    offsetForPinned = 0
    for tab in tabs
      # isPlaceholder could be duplicated here, but it would be just as fragile
      isPlaceholder = @tabBar.isPlaceholder tab
      tabWidth = if isPlaceholder then 0 else tab.clientWidth + @tabMargin
      placeholderOffset = if isPlaceholder then -@tabMargin else 0
      if maybePinned and @pinnedTabs.isPinned tab
        to = at
        isCovered = no
        zIndexBuffer = if tab is activeTab then numNormalTabs else 0
      else
        maybePinned = !isPlaceholder
        if normalTabs is 0
          at = -@scrollPos
        leftBound = normalTabs * 10
        rightBound = availableWidthForNormalTabs - tabWidth +
          (normalTabs + 1 - numNormalTabs) * 10
        to = bounded leftBound, rightBound, at
        zIndexOffset = Math.sign to - at
        isCovered = zIndexOffset isnt 0
        zIndexBuffer = if isCovered then 0 else numNormalTabs
        tab.classList.toggle 'covered', isCovered
        offsetForPinned = pinnedTabsWidth
        normalTabs++ unless isPlaceholder
      zIndex +=
        if isCovered then zIndexOffset else activeTabZIndexOffset
      style = tab.style
      style.left = "#{placeholderOffset + offsetForPinned + @paddingLeft + to}px"
      if not isPlaceholder
        style.zIndex = zIndex + zIndexBuffer
      at += tabWidth
      if tab is activeTab
        activeTabZIndexOffset = -1

    @availableWidthInLastLayout = availableWidthForNormalTabs
    @totalWidthInLastLayout = totalWidth
    @numNormalTabs = numNormalTabs
    return

  recalculateLayoutOnResize: ->
    if @totalWidthInLastLayout isnt @element.clientWidth
      @recalculateLayout()
    return

  recalculateLayoutToShow: (activeTab) ->
    availableWidth = @availableWidthInLastLayout
    activeTab = @tabBar.activeTab?.element

    at = -@scrollPos
    maybePinned = @pinnedTabs?
    offset = 0
    normalTabs = 0
    for tab in @element.children
      if maybePinned and @pinnedTabs.isPinned tab
        break if tab is activeTab
      else
        maybePinned = no
        tabWidth = tab.clientWidth + @tabMargin
        if tab is activeTab
          leftBound = normalTabs * 10
          rightBound = availableWidth - tabWidth +
            (normalTabs + 1 - @numNormalTabs) * 10
          to = bounded leftBound, rightBound, at
          offset = to - at
          break
        at += tabWidth
        normalTabs++

    @recalculateLayout offset
    return

  resetLayout: ->
    for tab in @element.children
      tab.style.removeProperty 'left'
      tab.style.removeProperty 'zIndex'

    @element.scrollLeft = @scrollPos
    @element.classList.remove('stacked-tab-bar')
    return

bounded = (min, max, value) ->
  Math.max(min, (Math.min max, value))

onDidActivatePackages = (packageNames, cb) ->
  numRequired = 0
  numActivated = 0
  for name in packageNames when atom.packages.isPackageLoaded name
    numRequired++

  # On our install
  for name in packageNames
    if atom.packages.isPackageActive name
      numActivated++
      if numActivated is numRequired
        cb()

  # On startup
  atom.packages.onDidActivatePackage (somePackage) ->
    if somePackage.name in packageNames
      numActivated++
      if numActivated is numRequired
        cb()
