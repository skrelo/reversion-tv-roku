sub init()
    m.gradient = m.top.findNode("gradient")
    m.hl = m.top.findNode("hl")
    m.profile = m.top.findNode("profile")
    m.avatarInitial = m.top.findNode("avatarInitial")
    m.profileName = m.top.findNode("profileName")
    m.profileHandle = m.top.findNode("profileHandle")
    m.itemHost = m.top.findNode("itemHost")
    m.brand = m.top.findNode("brand")

    ' Order per §6.6: Search, Home, Meetups, Livestreams, Continue, My List,
    ' then Settings pinned to the bottom.
    m.items = [
        { id: "search", icon: "search", label: "Search" }
        { id: "home", icon: "home", label: "Home" }
        { id: "meetups", icon: "meetups", label: "Meetups" }
        { id: "livestreams", icon: "livestreams", label: "Livestreams" }
        { id: "continue", icon: "continue", label: "Continue Watching" }
        { id: "mylist", icon: "mylist", label: "My List" }
        { id: "settings", icon: "settings", label: "Settings" }
    ]

    m.iconNodes = []
    m.labelNodes = []
    m.itemY = []
    m.iconX = 36
    m.labelX = 104
    m.topStart = 200
    m.stride = 78
    m.settingsY = 864

    i = 0
    for each it in m.items
        y = m.topStart + i * m.stride
        if it.id = "settings" then y = m.settingsY
        m.itemY.push(y)

        icon = CreateObject("roSGNode", "Poster")
        icon.uri = "pkg:/images/icons/ic_" + it.icon + ".png"
        icon.width = 44
        icon.height = 44
        icon.translation = [m.iconX, y + 10]
        m.itemHost.appendChild(icon)
        m.iconNodes.push(icon)

        lbl = CreateObject("roSGNode", "Label")
        lbl.width = 300
        lbl.height = 64
        lbl.translation = [m.labelX, y]
        lbl.vertAlign = "center"
        lbl.text = it.label
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/Montserrat-SemiBold.ttf"
        f.size = 26
        lbl.font = f
        lbl.visible = false
        m.itemHost.appendChild(lbl)
        m.labelNodes.push(lbl)

        i = i + 1
    end for

    updateActive()
    updateExpanded()
end sub

function indexOfId(id as string) as integer
    for i = 0 to m.items.Count() - 1
        if m.items[i].id = id then return i
    end for
    return -1
end function

sub updateExpanded()
    exp = (m.top.expanded = true)
    m.gradient.visible = exp
    m.profile.visible = exp
    m.brand.visible = exp
    for each lbl in m.labelNodes
        lbl.visible = exp
    end for
    ' Settings icon only shows when expanded (§6.6); collapsed strip hides it.
    settingsIdx = indexOfId("settings")
    if settingsIdx >= 0 then m.iconNodes[settingsIdx].visible = exp
    updateFocus()
    restyleIcons()
end sub

sub updateFocus()
    idx = m.top.focusedIndex
    if (m.top.expanded = true) and idx >= 0 and idx < m.itemY.Count() then
        m.hl.visible = true
        m.hl.translation = [20, m.itemY[idx]]
    else
        m.hl.visible = false
    end if
    restyleIcons()
end sub

sub updateActive()
    restyleIcons()
end sub

sub updateProfile()
    nm = m.top.userName
    if nm = invalid or nm = "" then nm = "Account"
    m.profileName.text = nm
    initial = UCase(Left(nm, 1))
    if initial = "" then initial = "R"
    m.avatarInitial.text = initial
    h = m.top.userHandle
    m.profileHandle.text = nz(h)
    m.profileHandle.visible = (nz(h) <> "")
end sub

' Active item icon = gold; focused = full white; otherwise dim. Uses Poster
' blendColor (white source PNGs tint cleanly).
sub restyleIcons()
    idx = m.top.focusedIndex
    activeId = m.top.activeId
    for i = 0 to m.iconNodes.Count() - 1
        isFocused = ((m.top.expanded = true) and i = idx)
        isActive = (m.items[i].id = activeId)
        if isFocused then
            m.iconNodes[i].blendColor = "0xFFFFFFFF"
        else if isActive then
            m.iconNodes[i].blendColor = "0xC9A84CFF"
        else
            m.iconNodes[i].blendColor = "0x8C9EB08C"
        end if
        if i < m.labelNodes.Count() then
            if isFocused then
                m.labelNodes[i].color = "0xFFFFFFFF"
            else if isActive then
                m.labelNodes[i].color = "0xC9A84CFF"
            else
                m.labelNodes[i].color = "0x8C9EB0FF"
            end if
        end if
    end for
end sub

function nz(v as dynamic) as string
    if v = invalid then return ""
    if type(v) = "String" or type(v) = "roString" then return v
    return ""
end function
