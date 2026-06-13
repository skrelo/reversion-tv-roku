' Search (TV_APP_SPEC §8). Left: persistent DynamicKeyboard with voice.
' Right: live debounced results rails (events + videos). Focus is explicit —
' the screen owns it, toggling between keyboard and results zones.

sub init()
    m.keyboard = createKeyboard()
    m.resultsPane = m.top.findNode("resultsPane")
    m.railsContent = m.top.findNode("railsContent")

    m.promptLabel = m.top.findNode("promptLabel")
    m.loadingLabel = m.top.findNode("loadingLabel")
    m.emptyLabel = m.top.findNode("emptyLabel")
    m.errorLabel = m.top.findNode("errorLabel")
    m.navHint = m.top.findNode("navHint")

    m.debounceTimer = m.top.findNode("debounceTimer")
    m.debounceTimer.observeField("fire", "onDebounce")

    ' Voice setup. "generic" = full-word search dictation. Sub-nodes must be
    ' reached via findNode, not chained property access (Roku runtime error &he4).
    m.keyboard.domain = "generic"
    teb = m.keyboard.findNode("textEditBox")
    if teb <> invalid then
        teb.voiceEnabled = true
        teb.voiceEntryType = "generic"
    end if
    m.keyboard.observeField("text", "onTextChanged")

    ' Results state.
    m.zone = "keyboard"    ' keyboard | results
    m.rails = []           ' array of { key, title, items[], type }
    m.railNodes = []       ' Rail SG nodes
    m.colByRail = []       ' focused column per rail
    m.railIndex = 0
    m.railStride = 290     ' vertical spacing between rails
    m.railTopPad = 60      ' y offset from pane top for first rail
    m.RESULTS_W = 1100     ' available width for results

    m.lastQuery = ""       ' dedup identical queries
    m.searchTask = invalid

    ' Results pane is fixed at x=740 in XML (right of the compact keyboard).
    m.RESULTS_W = 1120

    ' Initial state: show prompt, focus keyboard.
    showState("prompt")
    m.keyboard.setFocus(true)
end sub

' ── Keyboard node ──────────────────────────────────────────────────────
' DynamicMiniKeyboard bundles a remote-mic VoiceTextEditBox so dictation goes
' INTO our field (in-app search) rather than the OS global search. It needs OS
' 11.5+, which is the channel's minimum firmware, so it always exists here.
function createKeyboard() as object
    host = m.top.findNode("kbHost")
    kb = CreateObject("roSGNode", "DynamicMiniKeyboard")
    kb.id = "keyboard"
    kb.translation = [0, 0]
    host.appendChild(kb)
    return kb
end function

' ── Keyboard text → debounced search ──────────────────────────────────
sub onTextChanged()
    m.debounceTimer.control = "stop"
    q = m.keyboard.text
    if q = invalid then q = ""
    q = q.Trim()
    if Len(q) < 2 then
        m.lastQuery = ""
        clearResults()
        showState("prompt")
        return
    end if
    if q = m.lastQuery then return
    m.debounceTimer.control = "start"
end sub

sub onDebounce()
    q = m.keyboard.text
    if q = invalid then q = ""
    q = q.Trim()
    if Len(q) < 2 then return
    if q = m.lastQuery then return
    m.lastQuery = q
    doSearch(q)
end sub

sub doSearch(query as string)
    showState("loading")
    t = CreateObject("roSGNode", "ApiTask")
    t.request = ApiReq().search(query)
    t.observeField("response", "onSearchResponse")
    t.control = "RUN"
    m.searchTask = t
end sub

sub onSearchResponse()
    t = m.searchTask
    if t = invalid then return
    res = t.response
    if res = invalid or res.ok <> true then
        showState("error")
        m.errorLabel.text = "Search failed. Try again."
        return
    end if
    data = res.data
    if data = invalid then
        showState("empty")
        m.emptyLabel.text = "No results for " + Chr(34) + m.lastQuery + Chr(34)
        return
    end if

    events = arr(data.events)
    videos = arr(data.videos)

    if events.Count() = 0 and videos.Count() = 0 then
        showState("empty")
        m.emptyLabel.text = "No results for " + Chr(34) + m.lastQuery + Chr(34)
        return
    end if

    rails = []
    if events.Count() > 0 then
        rails.push({ key: "events", title: "Meetups & Livestreams", items: events, type: "event" })
    end if
    if videos.Count() > 0 then
        rails.push({ key: "videos", title: "Videos", items: videos, type: "video" })
    end if
    buildRails(rails)
    showState("results")
end sub

function arr(v as dynamic) as object
    if v <> invalid and GetInterface(v, "ifArray") <> invalid then return v
    return []
end function

' ── Rails ─────────────────────────────────────────────────────────────
sub buildRails(rails as object)
    clearResults()
    m.rails = rails
    i = 0
    for each rail in rails
        node = CreateObject("roSGNode", "Rail")
        node.translation = [0, m.railTopPad + i * m.railStride]
        node.rail = rail
        m.railsContent.appendChild(node)
        m.railNodes.push(node)
        m.colByRail.push(0)
        i = i + 1
    end for
    m.railIndex = 0
end sub

sub clearResults()
    m.railsContent.removeChildren(m.railsContent.getChildren(-1, 0))
    m.railNodes = []
    m.colByRail = []
    m.rails = []
    m.railIndex = 0
end sub

sub showState(state as string)
    m.promptLabel.visible = (state = "prompt")
    m.loadingLabel.visible = (state = "loading")
    m.emptyLabel.visible = (state = "empty")
    m.errorLabel.visible = (state = "error")
    ' The "press ► / ▼ to browse results" hint is only meaningful once there
    ' are cards to move into. Shown while the keyboard is focused; hidden once
    ' the user is already in the results zone.
    if m.navHint <> invalid then
        m.navHint.visible = (state = "results" and m.zone = "keyboard")
        if m.navHint.visible then centerNavHint()
    end if
    if state <> "results" then clearResults()
end sub

sub styleRailFocus()
    for i = 0 to m.railNodes.Count() - 1
        if m.zone = "results" and i = m.railIndex then
            m.railNodes[i].focusedCol = m.colByRail[i]
        else
            m.railNodes[i].focusedCol = -1
        end if
    end for
end sub

' ── Card selection ────────────────────────────────────────────────────
sub selectCard()
    if m.railIndex > m.rails.Count() - 1 then return
    rail = m.rails[m.railIndex]
    col = m.colByRail[m.railIndex]
    if rail = invalid or col > rail.items.Count() - 1 then return
    model = CardModel(rail.items[col], rail.type)
    if model.videoId <> "" then
        m.top.openVideoId = ""
        m.top.openVideoId = model.videoId
    else if model.eventId <> "" then
        m.top.openEventId = ""
        m.top.openEventId = model.eventId
    end if
end sub

' ── Focus / key routing ──────────────────────────────────────────────
sub enterResults()
    if m.railNodes.Count() = 0 then return
    m.zone = "results"
    if m.navHint <> invalid then m.navHint.visible = false
    ' Focus a node in the RESULTS subtree (a sibling of the keyboard), NOT
    ' m.top. m.top is the keyboard's ancestor, so setFocus(true) on it is a
    ' no-op while the keyboard (a descendant) already holds focus — the keyboard
    ' keeps eating the d-pad and the results highlight freezes. Focusing the
    ' results pane actually pulls focus off the keyboard; unhandled keys still
    ' bubble up to this component's onKeyEvent.
    m.resultsPane.setFocus(true)
    styleRailFocus()
end sub

sub enterKeyboard()
    m.zone = "keyboard"
    if m.navHint <> invalid then
        m.navHint.visible = (m.railNodes.Count() > 0)
        if m.navHint.visible then centerNavHint()
    end if
    styleRailFocus()
    m.keyboard.setFocus(true)
end sub

' The navHint LayoutGroup grows rightward from its translation. Center it under
' the keyboard by reading both bounding boxes at show time.
sub centerNavHint()
    if m.navHint = invalid then return
    hintW = 0
    r = m.navHint.boundingRect()
    if r <> invalid then hintW = r.width

    kbLeft = 80    ' kbHost x in screen coords
    kbW = 576      ' DynamicMiniKeyboard default; corrected from boundingRect below
    if m.keyboard <> invalid then
        kr = m.keyboard.boundingRect()
        if kr <> invalid and kr.width > 0 then kbW = kr.width
    end if

    x = kbLeft + kbW / 2 - hintW / 2
    if x < 20 then x = 20
    m.navHint.translation = [x, 905]
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.zone = "keyboard" then
        if key = "back" then
            m.top.popped = true
            return true
        end if
        ' Leave the keyboard for the results. The focused DynamicMiniKeyboard
        ' handles d-pad nav internally and only lets a directional key bubble up
        ' to us at its edge — so RIGHT bubbles at the right column and DOWN
        ' bubbles at the bottom row. Accept both so the jump to results is
        ' reachable from either edge (see navHint copy).
        if key = "right" or key = "down" then
            if m.railNodes.Count() > 0 then
                enterResults()
                return true
            end if
        end if
        return false
    end if

    ' results zone
    if key = "back" then
        enterKeyboard()
        return true
    end if
    if key = "left" then
        col = m.colByRail[m.railIndex]
        if col > 0 then
            m.colByRail[m.railIndex] = col - 1
            styleRailFocus()
        else
            enterKeyboard()
        end if
        return true
    end if
    if key = "right" then
        col = m.colByRail[m.railIndex]
        rail = m.rails[m.railIndex]
        if rail <> invalid and col < rail.items.Count() - 1 then
            m.colByRail[m.railIndex] = col + 1
            styleRailFocus()
        end if
        return true
    end if
    if key = "up" then
        if m.railIndex > 0 then
            m.railIndex = m.railIndex - 1
            styleRailFocus()
        else
            enterKeyboard()
        end if
        return true
    end if
    if key = "down" then
        if m.railIndex < m.railNodes.Count() - 1 then
            m.railIndex = m.railIndex + 1
            styleRailFocus()
        end if
        return true
    end if
    if key = "OK" then
        selectCard()
        return true
    end if
    return false
end function
