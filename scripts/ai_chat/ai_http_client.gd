extends Node

# AI HTTP 客户端
# 负责处理流式和非流式 HTTP 请求

signal stream_chunk_received(data: String)
signal stream_completed()
signal stream_error(error_message: String)

var http_client: HTTPClient
var is_streaming: bool = false
var stream_host: String = ""
var stream_port: int = 443
var stream_use_tls: bool = true
var request_start_time: float = 0.0
var connection_timeout: float = 15.0  # 连接超时时间（较短）
var response_timeout: float = 30.0   # 响应超时时间（正常超时）
var last_chunk_time: float = 0.0     # 最后接收数据块的时间

func _ready():
    http_client = HTTPClient.new()

func start_stream_request(url: String, headers: Array, json_body: String, timeout: float = 30.0):
    """启动流式HTTP请求"""
    print("=== 开始流式请求 ===")
    print("URL: %s" % url)
    print("超时设置: %.1f 秒" % timeout)
    
    # 设置连接超时（较短）和响应超时（正常）
    connection_timeout = min(timeout * 0.5, 15.0)  # 连接超时不超过15秒
    response_timeout = timeout  # 响应超时使用传入的超时时间
    
    print("连接超时: %.1f 秒, 响应超时: %.1f 秒, 总超时限制: %.1f 秒" % [connection_timeout, response_timeout, connection_timeout + response_timeout + 5.0])

    # 解析URL
    var base_url = url.split("/chat/completions")[0]
    var url_parts = base_url.replace("https://", "").replace("http://", "").split("/")
    stream_host = url_parts[0]
    stream_use_tls = url.begins_with("https://")
    stream_port = 443 if stream_use_tls else 80
    
    print("连接到: %s:%d (TLS: %s)" % [stream_host, stream_port, stream_use_tls])

    var tls_options = null
    if stream_use_tls:
        tls_options = TLSOptions.client()

    var err = http_client.connect_to_host(stream_host, stream_port, tls_options)
    if err != OK:
        is_streaming = false
        print("连接失败，错误码: %d" % err)
        stream_error.emit("连接失败: " + str(err))
        return

    request_start_time = Time.get_ticks_msec() / 1000.0
    print("请求开始时间: %.3f" % request_start_time)

    set_meta("stream_url", url)
    set_meta("stream_headers", headers)
    set_meta("stream_body", json_body)
    set_meta("stream_state", "connecting")

    is_streaming = true
    print("流式请求已启动，等待连接...")

func _process(_delta):
    """处理流式HTTP连接"""
    if not is_streaming:
        return

    # 检查超时
    var current_time = Time.get_ticks_msec() / 1000.0
    var elapsed_since_start = current_time - request_start_time

    # 全局总超时检查（防止请求无限挂起）
    # 总超时时间 = 连接超时 + 响应超时 + 缓冲时间(300秒)
    var total_timeout = connection_timeout + response_timeout + 300.0
    if elapsed_since_start > total_timeout:
        print("请求总超时（%.1f秒 > %.1f秒）" % [elapsed_since_start, total_timeout])
        is_streaming = false
        http_client.close()
        stream_error.emit("请求总超时")
        return

    # 根据当前状态检查特定的超时
    var stream_state = get_meta("stream_state", "")

    if stream_state == "connecting":
        # 连接阶段：检查连接超时
        if elapsed_since_start > connection_timeout:
            print("连接超时（%.1f秒）" % elapsed_since_start)
            is_streaming = false
            http_client.close()
            stream_error.emit("连接超时")
            return
    elif stream_state == "requesting" or stream_state == "receiving":
        # 响应阶段：检查响应空闲超时（从最后接收数据的时间开始计算）
        # 如果last_chunk_time未初始化，使用request_start_time作为基准
        var reference_time = last_chunk_time if last_chunk_time > 0 else request_start_time
        var elapsed_since_last_chunk = current_time - reference_time
        if elapsed_since_last_chunk > response_timeout:
            print("响应空闲超时（%.1f秒未收到数据，状态：%s）" % [elapsed_since_last_chunk, stream_state])
            is_streaming = false
            http_client.close()
            stream_error.emit("响应超时")
            return

    http_client.poll()
    var status = http_client.get_status()
    
    # 定期输出状态日志（每5秒一次）
    var log_interval = 5.0
    var last_log_time = get_meta("last_status_log_time", 0.0)
    if current_time - last_log_time > log_interval:
        print("HTTP状态检查: status=%d, stream_state=%s, elapsed=%.1fs" % [status, stream_state, elapsed_since_start])
        set_meta("last_status_log_time", current_time)

    match status:
        HTTPClient.STATUS_DISCONNECTED:
            if get_meta("stream_state", "") == "connecting":
                is_streaming = false
                print("连接断开（在connecting状态）")
                stream_error.emit("连接断开")
            elif is_streaming:
                # 在其他状态下断开也应该报错
                is_streaming = false
                print("连接意外断开（状态：%s）" % stream_state)
                stream_error.emit("连接断开")

        HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
            pass

        HTTPClient.STATUS_CONNECTED:
            if get_meta("stream_state", "") == "connecting":
                _send_stream_request()

        HTTPClient.STATUS_REQUESTING:
            pass

        HTTPClient.STATUS_BODY:
            _receive_stream_chunk()

        HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
            is_streaming = false
            stream_error.emit("连接错误: " + str(status))

func _send_stream_request():
    """发送流式请求"""
    print("连接已建立，发送请求...")
    var headers_array = get_meta("stream_headers", [])
    var body = get_meta("stream_body", "")

    var path = "/chat/completions"

    var err = http_client.request(HTTPClient.METHOD_POST, path, headers_array, body)
    if err != OK:
        is_streaming = false
        print("请求发送失败，错误码: %d" % err)
        stream_error.emit("请求发送失败: " + str(err))
        return

    set_meta("stream_state", "requesting")
    # 初始化最后数据块时间为请求开始时间
    last_chunk_time = request_start_time
    print("请求已发送，等待响应... (stream_state=requesting)")
func get_http_error_text(response_code: int) -> String:
    """根据HTTP响应码返回对应的错误信息文本"""
    match response_code:
        # 3xx: 重定向
        301: return "永久移动 - 请求的资源已被永久的移动到新URI"
        302: return "临时移动 - 请求的资源临时从不同的URI响应请求"
        304: return "未修改 - 客户端发送附带条件的请求时，服务器允许请求访问资源，但未满足条件的情况"
        # 4xx: 客户端错误
        400: return "参数错误 - 请检查模型名是否正确"
        401: return "未授权 - 请检查API密钥是否正确"
        403: return "请求被拒绝 - 可能是因为余额不足或未实名认证达到请求限制"
        404: return "网页不存在 - 请检查BaseURL是否正确"
        405: return "方法禁用 - 客户端请求中的方法被禁止"
        408: return "请求超时 - 可能炸了，请稍后再重试"
        413: return "请求实体过大 - 由于请求的实体过大，服务器无法处理，因此拒绝请求"
        415: return "不支持的媒体类型 - 服务器无法处理请求附带的媒体格式"
        418: return "我是一个茶壶（…？"
        429: return "请求限制 - 请求过于频繁，请稍后再试"      
        # 5xx: 服务器错误
        500: return "内部服务器错误 - 服务器炸了，请稍后再试"
        501: return "尚未实施 - 服务器不支持当前请求所需要的某个功能"
        502: return "错误网关 - 作为网关或者代理工作的服务器尝试执行请求时，从上游服务器接收到无效的响应"
        503: return "服务不可用 - 服务器过载或正在维护，请稍后再试"
        504: return "网关超时 - 服务器作为网关或代理，未能及时从上游服务器收到请求"
        505: return "HTTP版本不支持 - 服务器不支持请求中所使用的HTTP协议版本"
        522: return "连接超时 - 服务器连接超时"
        524: return "超时 - 服务器处理请求超时"
        # 网络相关错误（负数通常是Godot的网络错误）
        -1: return "网络错误 - 无法连接到服务器"
        -2: return "解析错误 - 无法解析响应数据"
        -3: return "连接超时 - 连接服务器超时"
        -4: return "SSL握手失败 - SSL/TLS握手失败"
        -5: return "无法解析主机名 - 无法解析服务器地址"
        # 其他
        8: return "Android生命周期管理问题，不是致命问题"
        31: return "请尝试重新保存AI配置"
        _:
            if response_code >= 400 and response_code < 500:
                return "客户端错误 %s - 请检查请求参数和格式" % response_code
            elif response_code >= 500 and response_code < 600:
                return "服务器错误 %s - 服务器处理请求时出现问题" % response_code
            elif response_code < 0:
                return "网络错误 %s - 网络连接或通信出现问题" % response_code
            else:
                return "未知错误代码: %s" % response_code

func _receive_stream_chunk():
    """接收流式数据块"""
    if http_client.has_response():
        # 首次接收到响应时更新状态
        if get_meta("stream_state", "") == "requesting":
            set_meta("stream_state", "receiving")
            print("开始接收响应数据 (stream_state=receiving)")
        
        var response_code = http_client.get_response_code()
        if response_code != 200:
            is_streaming = false
            var error_text = get_http_error_text(response_code)
            print("流式请求错误 - 响应码: %d, 错误: %s" % [response_code, error_text])
            stream_error.emit("%s (错误代码：%s)" % [error_text, response_code])
            return

        var chunk = http_client.read_response_body_chunk()
        if chunk.size() > 0:
            # 接收到数据时重置响应超时计时器
            last_chunk_time = Time.get_ticks_msec() / 1000.0
            var text = chunk.get_string_from_utf8()
            stream_chunk_received.emit(text)
        # 如果chunk为空但状态仍为BODY，继续等待（可能是网络延迟）

func stop_streaming():
    """停止流式请求"""
    print("停止流式请求（is_streaming=%s）" % is_streaming)
    is_streaming = false
    http_client.close()
    # 清理元数据
    remove_meta("stream_state")
    remove_meta("last_status_log_time")
    last_chunk_time = 0.0
    stream_completed.emit()
