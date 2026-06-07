' API request builders. Faithful 1:1 mirror of the contract in TV_APP_SPEC §4
' (and the Tizen src/lib/api.js). Each function returns a request descriptor
' { method, path, body, needsAuth } that ApiTask executes off-thread.
'
' Usage from a screen:
'   m.apiTask = CreateObject("roSGNode", "ApiTask")
'   m.apiTask.observeField("response", "onApiResponse")
'   m.apiTask.request = ApiReq().home()
'   m.apiTask.control = "RUN"

function ApiReq() as object
    return {
        ' ── Device pairing (no auth) §5 ──────────────────────────────
        requestPairingCode: function(deviceName as string) as object
            name = deviceName
            if name = invalid or name = "" then name = "Roku"
            return { method: "POST", path: "/device-auth/request", body: { device_name: name }, needsAuth: false }
        end function
        pollPairingCode: function(code as string) as object
            return { method: "GET", path: "/device-auth/poll?code=" + ReversionUrlEncode(code), body: invalid, needsAuth: false }
        end function

        ' ── Home / Events ────────────────────────────────────────────
        home: function() as object
            return { method: "GET", path: "/home", body: invalid, needsAuth: true }
        end function
        events: function(page as integer, perPage as integer) as object
            p = page
            if p < 1 then p = 1
            pp = perPage
            if pp < 1 then pp = 50
            return { method: "GET", path: "/events?page=" + p.ToStr() + "&per_page=" + pp.ToStr() + "&exclude_future=1", body: invalid, needsAuth: true }
        end function
        event: function(id as string) as object
            return { method: "GET", path: "/events/" + id, body: invalid, needsAuth: true }
        end function
        search: function(query as string) as object
            return { method: "GET", path: "/search?q=" + ReversionUrlEncode(query), body: invalid, needsAuth: true }
        end function

        ' ── Video ────────────────────────────────────────────────────
        streamUrl: function(videoId as string) as object
            return { method: "GET", path: "/videos/" + videoId + "/stream-url", body: invalid, needsAuth: true }
        end function
        saveProgress: function(videoId as string, seconds as integer) as object
            return { method: "PUT", path: "/videos/" + videoId + "/progress", body: { seconds: seconds }, needsAuth: true }
        end function

        ' ── Notes ────────────────────────────────────────────────────
        listNotes: function(videoId as string) as object
            return { method: "GET", path: "/videos/" + videoId + "/notes", body: invalid, needsAuth: true }
        end function
        createNote: function(videoId as string, note as object) as object
            return { method: "POST", path: "/videos/" + videoId + "/notes", body: note, needsAuth: true }
        end function
        deleteNote: function(videoId as string, noteId as string) as object
            return { method: "DELETE", path: "/videos/" + videoId + "/notes/" + noteId, body: invalid, needsAuth: true }
        end function

        ' ── TV-note QR companion ──────────────────────────────────────
        requestTvNoteCode: function(body as object) as object
            return { method: "POST", path: "/tv-notes/request", body: body, needsAuth: true }
        end function
        pollTvNoteCode: function(code as string) as object
            return { method: "GET", path: "/tv-notes/poll?code=" + ReversionUrlEncode(code), body: invalid, needsAuth: true }
        end function
        cancelTvNoteCode: function(code as string) as object
            return { method: "DELETE", path: "/tv-notes/" + ReversionUrlEncode(code), body: invalid, needsAuth: true }
        end function

        ' ── Library / bookmarks ───────────────────────────────────────
        library: function() as object
            return { method: "GET", path: "/library", body: invalid, needsAuth: true }
        end function
        addBookmark: function(videoId as string) as object
            return { method: "POST", path: "/videos/" + videoId + "/bookmark", body: {}, needsAuth: true }
        end function
        removeBookmark: function(videoId as string) as object
            return { method: "DELETE", path: "/videos/" + videoId + "/bookmark", body: invalid, needsAuth: true }
        end function
        addEventBookmark: function(eventId as string) as object
            return { method: "POST", path: "/events/" + eventId + "/bookmark", body: {}, needsAuth: true }
        end function
        removeEventBookmark: function(eventId as string) as object
            return { method: "DELETE", path: "/events/" + eventId + "/bookmark", body: invalid, needsAuth: true }
        end function

        ' ── Me / Legal / Version ──────────────────────────────────────
        me: function() as object
            return { method: "GET", path: "/me", body: invalid, needsAuth: true }
        end function
        legalDoc: function(document as string) as object
            return { method: "GET", path: "/legal/" + document, body: invalid, needsAuth: false }
        end function
        version: function() as object
            return { method: "GET", path: "/version", body: invalid, needsAuth: false }
        end function
    }
end function

function ReversionUrlEncode(s as string) as string
    ut = CreateObject("roUrlTransfer")
    return ut.Escape(s)
end function
