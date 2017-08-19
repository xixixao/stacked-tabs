{CompositeDisposable} = require 'atom'

module.exports =

  activate: ->
    ## Latch on center pane's tab bar
    atomTabs = atom.packages.getLoadedPackage('tabs').mainModule
    atom.packages.onDidActivatePackage (packageObj) =>
      if packageObj.name is 'tabs'
        @activateAfterTabBar packageObj

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
      # TODO: do I need set Immediate to avoid race condition?
      @recalculateLayout()

    @subscriptions.add pane.onDidMoveItem ({item, newIndex}) =>
      # TODO: do I need set Immediate to avoid race condition?
      @recalculateLayout()

    @subscriptions.add pane.onDidRemoveItem ({item}) =>
      # TODO: do I need set Immediate to avoid race condition?
      @recalculateLayout()

    @subscriptions.add pane.onDidChangeFlexScale =>
      window.requestAnimationFrame =>
        @recalculateLayout()

    @element.addEventListener "dragover", =>
      # TODO: do I need set Immediate to avoid race condition?
      @recalculateLayout()

    # TODO: no way to observe closing of side docks :(

    # Used to react to side docks resizing
    window.addEventListener 'mouseup', => @recalculateLayoutOnResize()

    # Normal window resizing
    window.addEventListener 'resize', => @recalculateLayoutOnResize()

    ## Monkey patch the tab bar
    # I use monkey-patching because I need to prevent the `scrollIntoView`
    stackedTabs = @
    setActiveTab = (tabView) ->
      if tabView? and tabView isnt @activeTab
        @activeTab?.element.classList.remove('active')
        @activeTab = tabView
        @activeTab.element.classList.add('active')

        # @activeTab.element.scrollIntoView(false)
        stackedTabs.recalculateLayoutToShow @activeTab.element

    @tabBar.setActiveTab = setActiveTab.bind(@tabBar)

    ## Initialize state
    @scrollPos = @element.scrollLeft
    @element.classList.add('stacked-tab-bar')
    @element.addEventListener 'mousewheel', @onMouseWheel.bind(this)

    ## Kick of first layout
    window.requestAnimationFrame =>
      @recalculateLayout()

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

  onMouseWheel: (event) ->
    @recalculateLayout event.wheelDeltaX

  recalculateLayout: (deltaX = 0) ->
    availableWidth = @element.clientWidth

    totalWidth = 0
    for tab in @element.children
      totalWidth += tab.clientWidth
    numTabs = @element.children.length

    @scrollPos = Math.max 0,
      Math.min totalWidth - availableWidth, @scrollPos - deltaX

    at = -@scrollPos
    zindex = numTabs
    for tab, i in @element.children
      width = tab.clientWidth
      style = tab.style
      leftBound = i * 10
      rightBound = availableWidth - width + (i + 1 - numTabs) * 10
      left = at < leftBound
      right = at > rightBound
      to = Math.max leftBound, Math.min rightBound, at
      zindex += Math.sign to - at
      style.left = "#{to}px"
      # isPlaceholder could be duplicated here, but it would be just as fragile
      if not @tabBar.isPlaceholder tab
        style.zIndex = zindex
      at += width
    @availableWidthInLastLayout = @element.clientWidth

  recalculateLayoutOnResize: ->
    if @availableWidthInLastLayout isnt @element.clientWidth
      @recalculateLayout()

  recalculateLayoutToShow: (activeTab) ->
    availableWidth = @element.clientWidth
    pos = 0
    for tab in @element.children
      break if tab is activeTab
      pos += tab.clientWidth
    # As if to try to display the activeTab in the middle of the tab bar
    @recalculateLayout @scrollPos + availableWidth // 2 - pos

  resetLayout: ->
    for tab in @element.children
      tab.style.removeProperty 'left'
      tab.style.removeProperty 'zIndex'

    @element.scrollLeft = @scrollPos
