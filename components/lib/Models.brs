' Data helpers mirroring the Tizen components (Card.jsx, Hero.jsx, Home.jsx)
' and TV_APP_SPEC §4.1, §6. Resolve the flat-or-nested event/video shapes,
' art precedence, progress fractions, year grouping and My List merge.

' ── Image right-sizing (TV_APP_SPEC §2 Polish; mirrors lib/img.js) ───────
function SizedImage(url as dynamic, width as integer) as string
    if url = invalid or type(url) <> "String" and type(url) <> "roString" then return ""
    s = url
    if s = "" then return ""
    if Instr(1, s, "imagedelivery.net") > 0 then
        ' Path: /<hash>/<id>/<variant> → swap trailing variant for a width spec.
        q = Instr(1, s, "?")
        if q > 0 then s = Left(s, q - 1)
        slash = 0
        ' Find last "/" and replace the segment after it.
        for i = Len(s) to 1 step -1
            if Mid(s, i, 1) = "/" then slash = i : exit for
        end for
        if slash > 0 then
            return Left(s, slash) + "w=" + width.ToStr() + ",quality=85,format=auto"
        end if
        return s
    end if
    if Instr(1, s, "cloudflarestream.com") > 0 and Instr(1, s, "/thumbnails/") > 0 then
        sep = "?"
        if Instr(1, s, "?") > 0 then sep = "&"
        return s + sep + "width=" + width.ToStr()
    end if
    return s
end function

' Height-constrained variant for wordmarks/logos: ask the CDN for an image at a
' target HEIGHT (aspect preserved) so we never force a width/height box that
' distorts or upscales. The Poster then renders it near 1:1 with no stretch.
function SizedImageH(url as dynamic, height as integer) as string
    if url = invalid or type(url) <> "String" and type(url) <> "roString" then return ""
    s = url
    if s = "" then return ""
    if Instr(1, s, "imagedelivery.net") > 0 then
        q = Instr(1, s, "?")
        if q > 0 then s = Left(s, q - 1)
        slash = 0
        for i = Len(s) to 1 step -1
            if Mid(s, i, 1) = "/" then slash = i : exit for
        end for
        if slash > 0 then
            return Left(s, slash) + "h=" + height.ToStr() + ",quality=90,format=auto"
        end if
        return s
    end if
    if Instr(1, s, "cloudflarestream.com") > 0 and Instr(1, s, "/thumbnails/") > 0 then
        sep = "?"
        if Instr(1, s, "?") > 0 then sep = "&"
        return s + sep + "height=" + height.ToStr()
    end if
    return s
end function

' Padded variant for the centered carousel wordmark. Cloudflare Images pads the
' wordmark onto an EXACT w*h transparent canvas (fit=pad + background=transparent),
' centering the artwork regardless of its native aspect / line count. Roku Posters
' can't horizontally center a variable-width image on their own, so we let the CDN
' bake the centering into a fixed-size transparent image we drop at hero top-center.
function PaddedImage(url as dynamic, w as integer, h as integer) as string
    if url = invalid or type(url) <> "String" and type(url) <> "roString" then return ""
    s = url
    if s = "" then return ""
    if Instr(1, s, "imagedelivery.net") > 0 then
        q = Instr(1, s, "?")
        if q > 0 then s = Left(s, q - 1)
        slash = 0
        for i = Len(s) to 1 step -1
            if Mid(s, i, 1) = "/" then slash = i : exit for
        end for
        if slash > 0 then
            return Left(s, slash) + "w=" + w.ToStr() + ",h=" + h.ToStr() + ",fit=pad,background=transparent,quality=90,format=auto"
        end if
        return s
    end if
    return s
end function

function firstNonEmpty(values as object) as string
    for each v in values
        if v <> invalid and (type(v) = "String" or type(v) = "roString") and v <> "" then return v
    end for
    return ""
end function

' ── Card view-model (mirror of Card.jsx) ────────────────────────────────
' railType: "video" | "event" | "mixed". Returns everything a RailCard needs.
function CardModel(item as object, railType as string) as object
    itemType = railType
    if item._bookmarkType <> invalid and item._bookmarkType <> "" then itemType = item._bookmarkType
    isVideo = (itemType = "video")

    hasBaked = (item.card_poster_url <> invalid and item.card_poster_url <> "")
    art = firstNonEmpty([item.card_poster_url, item.cover_url, item.poster_url])
    wordmark = firstNonEmpty([item.wordmark_url, item.event_wordmark_url])

    nestedEvent = invalid
    if item.event <> invalid and GetInterface(item.event, "ifAssociativeArray") <> invalid then nestedEvent = item.event

    eventName = item.event_title
    if eventName = invalid or eventName = "" then
        if nestedEvent <> invalid then
            eventName = firstNonEmpty([nestedEvent.name, nestedEvent.title])
        end if
    end if
    if eventName = invalid then eventName = ""
    if eventName = "" and item.event_name <> invalid then eventName = item.event_name

    ' Progress fraction (RED bar). Video rows: flat progress/duration.
    ' Event rows: from last_in_progress_video. §6.5
    frac = 0.0
    if isVideo then
        frac = fraction(item.progress_seconds, item.duration_seconds)
    else
        lip = item.last_in_progress_video
        if lip <> invalid then frac = fraction(lip.progress_seconds, lip.duration_seconds)
    end if

    belowTitle = ""
    if isVideo and item.title <> invalid then belowTitle = item.title
    belowMeta = firstNonEmpty([item.session_date, item.video_date])

    overlayTitle = ""
    if not hasBaked and wordmark = "" then
        if isVideo then
            overlayTitle = eventName
        else
            overlayTitle = firstNonEmpty([item.title, eventName])
        end if
    end if

    badge = ""
    if item.is_new = true then
        badge = "NEW"
    else if item._bookmarkType = "event" then
        badge = "EVENT"
    else if item._bookmarkType = "video" then
        badge = "VIDEO"
    end if

    ' Selection targets. §6.5 (video → play, event → detail).
    nestedEventId = invalid
    if nestedEvent <> invalid then nestedEventId = nestedEvent.id
    eventId = ""
    videoId = ""
    if itemType = "video" then
        videoId = toStr(item.id)
        eventId = toStr(firstDefined(item.event_id, nestedEventId))
    else if itemType = "event" then
        eventId = toStr(item.id)
    else
        eventId = toStr(firstDefined(item.event_id, firstDefined(nestedEventId, item.id)))
    end if

    return {
        art: art
        hasBaked: hasBaked
        wordmark: wordmark
        overlayTitle: overlayTitle
        belowTitle: belowTitle
        belowMeta: belowMeta
        badge: badge
        progress: frac
        isContinue: (isVideo and frac > 0)
        videoId: videoId
        eventId: eventId
        spotlight: SpotlightModel(item, eventName, nestedEvent)
    }
end function

' Spotlight ALWAYS describes the parent EVENT (never the video). §6.3
function SpotlightModel(item as object, eventName as string, nestedEvent as object) as object
    backdrop = ""
    if nestedEvent <> invalid then backdrop = firstNonEmpty([nestedEvent.backdrop_url, nestedEvent.poster_url])
    if backdrop = "" then backdrop = firstNonEmpty([item.backdrop_url, item.poster_url, item.cover_url, item.card_poster_url])

    wm = item.event_wordmark_url
    if wm = invalid or wm = "" then
        if nestedEvent <> invalid then wm = nestedEvent.wordmark_url
    end if
    if wm = invalid or wm = "" then wm = item.wordmark_url
    if wm = invalid then wm = ""

    sd = item.event_session_date
    if sd = invalid or sd = "" then
        if nestedEvent <> invalid then sd = nestedEvent.session_date
    end if
    if sd = invalid or sd = "" then sd = item.session_date
    if sd = invalid then sd = ""

    vc = item.event_video_count
    if vc = invalid then
        if nestedEvent <> invalid then vc = nestedEvent.video_count
    end if
    if vc = invalid then vc = item.video_count
    if vc = invalid then vc = 0

    tagline = item.event_tv_subtitle
    if tagline = invalid or tagline = "" then
        if nestedEvent <> invalid then tagline = nestedEvent.tv_subtitle
    end if
    if tagline = invalid or tagline = "" then tagline = item.tv_subtitle
    if tagline = invalid then tagline = ""

    desc = item.event_short_description
    if desc = invalid or desc = "" then
        if nestedEvent <> invalid then desc = nestedEvent.short_description
    end if
    if desc = invalid or desc = "" then desc = item.short_description
    if desc = invalid then desc = ""

    videoTitle = ""
    if item._bookmarkType = "video" and item.title <> invalid then videoTitle = item.title

    title = eventName
    if title = "" and item.title <> invalid then title = item.title

    return {
        backdropUrl: backdrop
        wordmarkUrl: wm
        title: title
        videoTitle: videoTitle
        sessionDate: sd
        videoCount: vc
        tagline: tagline
        description: desc
    }
end function

' Carousel slide view-model from a hero_carousel event. §6.2
function HeroSlideModel(ev as object) as object
    inProgress = ev.last_in_progress_video
    firstVideo = ev.first_video
    target = inProgress
    if target = invalid then target = firstVideo
    watchLabel = "Watch"
    if inProgress <> invalid then watchLabel = "Continue"

    targetId = ""
    if target <> invalid then targetId = toStr(target.id)

    return {
        backdropUrl: firstNonEmpty([ev.backdrop_url, ev.poster_url])
        wordmarkUrl: nz(ev.wordmark_url)
        title: nz(ev.title)
        tagline: nz(ev.tv_subtitle)
        description: nz(ev.short_description)
        sessionDate: nz(ev.session_date)
        videoCount: intOr(ev.video_count, 0)
        watchLabel: watchLabel
        hasTarget: (target <> invalid)
        targetVideoId: targetId
        eventId: toStr(ev.id)
    }
end function

function CountLabel(n as integer) as string
    if n <= 0 then return ""
    if n = 1 then return "1 video"
    return n.ToStr() + " videos"
end function

' ── My List merge (event + video bookmarks, newest first). §6.5 ─────────
function BuildMyList(eventBookmarks as object, videoBookmarks as object) as object
    all = []
    if eventBookmarks <> invalid then
        for each e in eventBookmarks
            e._bookmarkType = "event"
            e._bookmarkedAt = nz(e.bookmarked_at)
            all.push(e)
        end for
    end if
    if videoBookmarks <> invalid then
        for each v in videoBookmarks
            v._bookmarkType = "video"
            v._bookmarkedAt = nz(v.bookmarked_at)
            all.push(v)
        end for
    end if
    ' Sort by bookmarked_at desc (string compare on ISO dates).
    n = all.Count()
    for i = 0 to n - 2
        for j = 0 to n - 2 - i
            if all[j]._bookmarkedAt < all[j + 1]._bookmarkedAt then
                tmp = all[j] : all[j] = all[j + 1] : all[j + 1] = tmp
            end if
        end for
    end for
    return all
end function

' ── Year-grouped rails (Meetups / Livestreams catalogs). §6.7 ───────────
function YearGroupedRails(events as object, keyPrefix as string, ungroupedLabel as string) as object
    groups = {}
    order = []
    if events <> invalid then
        for each ev in events
            year = parseYear(nz(ev.session_date))
            k = year.ToStr()
            if groups[k] = invalid then
                groups[k] = []
                order.push(year)
            end if
            groups[k].push(ev)
        end for
    end if
    ' years desc, then 0 (ungrouped) last.
    years = []
    for each y in order
        if y > 0 then years.push(y)
    end for
    ' simple desc sort
    n = years.Count()
    for i = 0 to n - 2
        for j = 0 to n - 2 - i
            if years[j] < years[j + 1] then
                t = years[j] : years[j] = years[j + 1] : years[j + 1] = t
            end if
        end for
    end for
    if groups["0"] <> invalid then years.push(0)

    rails = []
    for each y in years
        items = groups[y.ToStr()]
        if items <> invalid and items.Count() > 0 then
            ttl = y.ToStr()
            if y = 0 then ttl = ungroupedLabel
            rails.push({ key: keyPrefix + "_" + y.ToStr(), title: ttl, items: items, type: "event" })
        end if
    end for
    return rails
end function

function parseYear(s as string) as integer
    if s = invalid or Len(s) < 4 then return 0
    for i = 1 to Len(s) - 3
        chunk = Mid(s, i, 4)
        if isAllDigits(chunk) then
            v = chunk.ToInt()
            if v >= 2000 and v <= 2099 then return v
        end if
    end for
    return 0
end function

function isAllDigits(s as string) as boolean
    for each ch in s.Split("")
        if ch < "0" or ch > "9" then return false
    end for
    return (Len(s) > 0)
end function

' ── Small utilities ─────────────────────────────────────────────────────
function fraction(num as dynamic, den as dynamic) as float
    n = numOr(num, 0)
    d = numOr(den, 0)
    if d <= 0 or n <= 0 then return 0.0
    f = n / d
    if f > 1.0 then f = 1.0
    if f < 0.0 then f = 0.0
    return f
end function

function nz(v as dynamic) as string
    if v = invalid then return ""
    if type(v) = "String" or type(v) = "roString" then return v
    return ""
end function

function toStr(v as dynamic) as string
    if v = invalid then return ""
    t = type(v)
    if t = "String" or t = "roString" then return v
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return v.ToStr()
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Int(v).ToStr()
    return ""
end function

function intOr(v as dynamic, fallback as integer) as integer
    if v = invalid then return fallback
    t = type(v)
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return v
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return Int(v)
    if t = "String" or t = "roString" then return v.ToInt()
    return fallback
end function

function numOr(v as dynamic, fallback as float) as float
    if v = invalid then return fallback
    t = type(v)
    if t = "Integer" or t = "roInt" or t = "roInteger" or t = "LongInteger" or t = "roLongInteger" then return v
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return v
    if t = "String" or t = "roString" then return v.ToFloat()
    return fallback
end function

function firstDefined(a as dynamic, b as dynamic) as dynamic
    if a <> invalid and a <> "" then return a
    return b
end function
