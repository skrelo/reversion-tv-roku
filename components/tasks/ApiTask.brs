sub init()
    m.top.functionName = "execRequest"
end sub

sub execRequest()
    cfg = ReversionConfig()
    req = m.top.request
    if req = invalid then
        m.top.response = { ok: false, status: 0, data: {}, error: "No request" }
        return
    end if

    method = req.method
    if method = invalid then method = "GET"
    path = req.path
    if path = invalid then path = ""
    url = cfg.BASE_URL + cfg.API_PREFIX + path

    token = invalid
    if req.needsAuth = true then
        token = GetAuthToken()
    end if

    bodyStr = invalid
    if req.body <> invalid then
        bodyStr = FormatJson(req.body)
    end if

    ' Retry transient failures (network / 5xx) up to RETRY_MAX with backoff. §2
    attempt = 0
    result = invalid
    while attempt <= cfg.RETRY_MAX
        result = doTransfer(method, url, bodyStr, token, cfg)
        ' Success or a non-retryable status -> stop.
        if result.status >= 200 and result.status < 300 then exit while
        if result.status >= 400 and result.status < 500 then exit while
        if attempt >= cfg.RETRY_MAX then exit while
        ms = cfg.RETRY_BACKOFF_MS[attempt]
        if ms = invalid then ms = 1500
        sleep(ms)
        attempt = attempt + 1
    end while

    ok = (result.status >= 200 and result.status < 300)
    data = {}
    if result.bodyText <> invalid and result.bodyText <> "" then
        parsed = ParseJson(result.bodyText)
        if parsed <> invalid then data = parsed
    end if

    m.top.response = {
        ok: ok
        status: result.status
        data: data
        error: result.error
    }
end sub

' One HTTP round-trip via roUrlTransfer with a message-port wait so we honor
' the configured timeout instead of blocking forever.
function doTransfer(method as string, url as string, bodyStr as dynamic, token as dynamic, cfg as object) as object
    ut = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    ut.SetMessagePort(port)
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.SetUrl(url)
    ut.AddHeader("Accept", "application/json")
    ut.AddHeader("Content-Type", "application/json")
    if token <> invalid and token <> "" then
        ut.AddHeader("Authorization", "Bearer " + token)
    end if
    ut.EnableEncodings(true)

    started = false
    if method = "GET" then
        started = ut.AsyncGetToString()
    else
        ut.SetRequest(method)
        b = bodyStr
        if b = invalid then b = ""
        started = ut.AsyncPostFromString(b)
    end if

    if not started then
        return { status: 0, bodyText: invalid, error: "Failed to start request" }
    end if

    msg = wait(cfg.HTTP_TIMEOUT_MS, port)
    if msg = invalid then
        ut.AsyncCancel()
        return { status: 0, bodyText: invalid, error: "Request timed out" }
    end if

    if type(msg) = "roUrlEvent" then
        code = msg.GetResponseCode()
        bodyText = msg.GetString()
        err = invalid
        if code <= 0 then err = msg.GetFailureReason()
        return { status: code, bodyText: bodyText, error: err }
    end if

    return { status: 0, bodyText: invalid, error: "Unexpected response" }
end function
