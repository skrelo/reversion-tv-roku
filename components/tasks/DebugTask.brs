' TEMPORARY cert diagnostic — see DebugTask.xml. Loops on the `beacon` field and
' POSTs each event to the backend debug sink. Synchronous POST on this task
' thread (never the render thread); response is ignored (fire-and-forget).
sub init()
    m.top.functionName = "runLoop"
    m.top.control = "RUN"
end sub

sub runLoop()
    cfg = ReversionConfig()
    m.url = cfg.BASE_URL + cfg.API_PREFIX + "/tv-debug"
    m.sent = 0
    port = CreateObject("roMessagePort")
    m.top.observeField("beacon", port)
    ' Drain anything queued before the observer was live (cold-start beacons).
    drain()
    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent" then drain()
    end while
end sub

' POST every queue entry we haven't sent yet. The queue only grows (render
' thread appends), so tracking an index is race-free without mutating it here.
sub drain()
    q = m.top.beacon
    if q = invalid then return
    n = q.Count()
    while m.sent < n
        postBeacon(q[m.sent])
        m.sent = m.sent + 1
    end while
end sub

sub postBeacon(b as object)
    ut = CreateObject("roUrlTransfer")
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.SetUrl(m.url)
    ut.AddHeader("Content-Type", "application/json")
    ut.AddHeader("Accept", "application/json")
    ut.SetRequest("POST")
    ut.PostFromString(FormatJson(b))
end sub
