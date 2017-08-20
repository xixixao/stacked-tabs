{CompositeDisposable} = require 'atom'

module.exports =

  activate: ->
    ## Latch on center pane's tab bar
    atomTabs = atom.packages.getLoadedPackage('tabs').mainModule
    atom.packages.onDidActivatePackage (packageObj) =>
      if packageObj.name is 'tabs'
        @activateAfterTabBar packageObj
    return

  activateAfterTabBar: (atomTabsPackage) ->
    atomTabs = atomTabsPackage.mainModule
    @tabBar = atomTabs.tabBarViews
      .filter((tabBar) => tabBar.location is 'center')[0]

    # I could easily get the pane from atom.workspace.getPanes()
    # but I need the tabBar for monkey-patching
    pane = @tabBar.pane

    # Another way to get the element would be to get the first child of the pane
    @element = @tabBar.element

    ## Subscribe to events, letting @tabBar to react first
    @subscriptions = new CompositeDisposable

    @subscriptions.add pane.onDidAddItem ({item, index}) =>
      @recalculateLayout()

    @subscriptions.add pane.onDidMoveItem ({item, newIndex}) =>
      @recalculateLayout()

    @subscriptions.add pane.onDidRemoveItem ({item}) =>
      @recalculateLayout()

    @subscriptions.add pane.onDidChangeFlexScale =>
      window.requestAnimationFrame =>
        @recalculateLayout()

    @element.addEventListener "dragover", =>
      @recalculateLayout()

    # TODO: no way to observe closing of side docks :(

    # Used to react to side docks resizing
    window.addEventListener 'mouseup', => @recalculateLayoutOnResize()

    # Normal window resizing
    window.addEventListener 'resize', => @recalculateLayoutOnResize()

    ## Kicks of first layout as well
    atom.themes.onDidChangeActiveThemes =>
      @recalculateLayoutBasedOnTheme()

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

    @tabBar.setActiveTab = setActiveTab.bind(@tabBar)

    ## Initialize state
    @scrollPos = @element.scrollLeft
    @element.classList.add('stacked-tab-bar')
    @element.addEventListener 'mousewheel', @onMouseWheel.bind(this)
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
    @element.removeEventListener 'mousewheel', @onMouseWheel.bind(this)
    window.removeEventListener 'mouseup', => @recalculateLayoutOnResize()
    window.removeEventListener 'resize', => @recalculateLayoutOnResize()

    ## Reset styles
    @element.classList.remove('stacked-tab-bar')
    return

  onMouseWheel: (event) ->
    @recalculateLayout event.wheelDeltaX
    return

  recalculateLayout: (deltaX = 0) ->
    tabs = @element.children
    if tabs.length is 0
      return

    if !@tabMargin?
      tabStyle = window.getComputedStyle @element.children[0]
      @tabMargin = parseInt(tabStyle.marginLeft) +
        parseInt(tabStyle.marginRight)

    availableWidth = @element.clientWidth - @padding

    totalWidth = 0
    for tab in tabs
      totalWidth += tab.clientWidth + @tabMargin
    numTabs = tabs.length

    @scrollPos = Math.max 0,
      Math.min totalWidth - availableWidth, @scrollPos - deltaX

    at = -@scrollPos
    zindex = numTabs
    activeTabZIndexOffset = 1
    # using tabBar as optimization over classList
    activeTab = @tabBar.activeTab.element
    for tab, i in tabs
      width = tab.clientWidth + @tabMargin
      style = tab.style
      leftBound = i * 10
      rightBound = availableWidth - width + (i + 1 - numTabs) * 10
      to = Math.max leftBound, Math.min rightBound, at
      zIndexOffset = Math.sign to - at
      isCovered = zIndexOffset isnt 0
      tab.classList.toggle 'covered', isCovered
      zindex +=
        if isCovered then zIndexOffset else activeTabZIndexOffset
      style.left = "#{@paddingLeft + to}px"
      # isPlaceholder could be duplicated here, but it would be just as fragile
      if not @tabBar.isPlaceholder tab
        style.zIndex = zindex
      at += width
      if tab is activeTab
        activeTabZIndexOffset = -1

    @availableWidthInLastLayout = availableWidth
    return

  recalculateLayoutOnResize: ->
    if @availableWidthInLastLayout isnt @element.clientWidth
      @recalculateLayout()
    return

  recalculateLayoutToShow: (activeTab) ->
    availableWidth = @element.clientWidth
    pos = 0
    for tab in @element.children
      break if tab is activeTab
      pos += tab.clientWidth
    # As if to try to display the activeTab in the middle of the tab bar
    @recalculateLayout @scrollPos + availableWidth // 2 - pos
    return

  resetLayout: ->
    for tab in @element.children
      tab.style.removeProperty 'left'
      tab.style.removeProperty 'zIndex'

    @element.scrollLeft = @scrollPos
    return
