sub init()
    m.title = m.top.findNode("title")
    m.cardsRow = m.top.findNode("cardsRow")
    m.scrollAnim = m.top.findNode("scrollAnim")
    m.scrollInterp = m.top.findNode("scrollInterp")
    m.cards = []
    m.stride = 328       ' card 300 + gap 28
    m.viewWidth = 1700
    m.rowY = 48
end sub

sub renderRail()
    rail = m.top.rail
    m.cardsRow.removeChildren(m.cardsRow.getChildren(-1, 0))
    m.cards = []
    if rail = invalid then return

    m.title.text = UCase(nz(rail.title))
    items = rail.items
    if items = invalid then items = []
    railType = nz(rail.type)
    if railType = "" then railType = "event"

    hideOverlay = (rail.hideOverlay = true)
    i = 0
    for each item in items
        card = CreateObject("roSGNode", "RailCard")
        card.translation = [i * m.stride, 0]
        md = CardModel(item, railType)
        ' Event Detail's Videos rail renders the title/date BELOW the cover, so
        ' the on-art overlay title would duplicate it. §7
        if hideOverlay then md.overlayTitle = ""
        card.model = md
        m.cardsRow.appendChild(card)
        m.cards.push(card)
        i = i + 1
    end for
    m.top.itemCount = m.cards.Count()
    m.scrollAnim.control = "stop"
    m.cardsRow.translation = [0, m.rowY]
    updateFocus()
end sub

sub updateFocus()
    col = m.top.focusedCol
    for i = 0 to m.cards.Count() - 1
        m.cards[i].focused = (i = col)
    end for
    if col < 0 then return

    offset = col * m.stride
    totalWidth = m.cards.Count() * m.stride
    maxOffset = totalWidth - m.viewWidth
    if maxOffset < 0 then maxOffset = 0
    if offset > maxOffset then offset = maxOffset
    if offset < 0 then offset = 0

    target = [-offset, m.rowY]
    cur = m.cardsRow.translation
    if Abs(cur[0] - target[0]) < 1 then return
    m.scrollAnim.control = "stop"
    m.scrollInterp.keyValue = [cur, target]
    m.scrollAnim.control = "start"
end sub
