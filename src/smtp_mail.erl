-module(smtp_mail).

%%%=======================STATEMENT====================
-description("smtp_mail").
-author("yhw").

%%%=======================EXPORT=======================
-export([init_mail/7, send/1, send_msg/3, recv_msg/3, send/3]).

%%%=======================INCLUDE======================

%%%=======================DEFINE======================
-define(IS_SSL, 465).
-define(NO_SSL, 25).

-define(FMT(Fmt, Args), io:format(Fmt, Args)).
-define(SENDFMT, "Client Send: ~p~n").
-define(RECVFMT, "server Recv: ~p~n").
%%%=======================RECORD=======================
-record(email, {
    server,
    user,
    password,
    ssl = true,
    subject,
    content,
    attachment,
    receiver
}).
%%%=======================TYPE=========================
%%-type my_type() :: atom() | integer().


%%%=================EXPORTED FUNCTIONS=================
init_mail(MailSever, Sender, Password, Subject, Content, Attachment, Receiver) ->
    #email{server = MailSever, user = Sender, password = Password, subject = Subject,
        content = Content, attachment = Attachment, receiver = Receiver}.

%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
send(EMail) ->
    SSLBool = EMail#email.ssl,
    {ok, Sock} = if
        SSLBool ->
            ssl:connect(EMail#email.server, ?IS_SSL, [binary, {active, false}, {packet, 0}]);
        true ->
            gen_tcp:connect(EMail#email.server, ?NO_SSL, [binary, {active, false}, {packet, 0}])
    end,
    %SMTP协议的握手信号
    send_msg(SSLBool, Sock, "HELO " ++ EMail#email.server ++ "\r\n"),
    recv_msg(SSLBool, Sock, 0),
    %开始认证登录
    send_msg(SSLBool, Sock, "AUTH LOGIN\r\n"),
    recv_msg(SSLBool, Sock, 0),
    send_msg(SSLBool, Sock, base64:encode(EMail#email.user)),
    send_msg(SSLBool, Sock, "\r\n"),
    send_msg(SSLBool, Sock, base64:encode(EMail#email.password)),
    send_msg(SSLBool, Sock, "\r\n"),
    %%指定邮件发送者的地址
    send_msg(SSLBool, Sock, "MAIL FROM:" ++ EMail#email.user ++ "\r\n"),
    recv_msg(SSLBool, Sock, 0),
    %%指定邮件收件者的地址
    lists:foreach(fun(Rec) ->
        send_msg(SSLBool, Sock, "RCPT TO:" ++ Rec ++ "\r\n"),
        recv_msg(SSLBool, Sock, 0)
    end, EMail#email.receiver),
    %%发送程序开始准备发送内容
    send_msg(SSLBool, Sock, "DATA\r\n"),
    recv_msg(SSLBool, Sock, 0),
    %%开始发送邮件头部信息
    %%收件人发件人
    lists:foreach(fun(Rec) ->
        send_msg(SSLBool, Sock, "TO:" ++ Rec ++ "\r\n")
    end, EMail#email.receiver),
    send_msg(SSLBool, Sock, "FROM:<" ++ EMail#email.user ++ ">\r\n"),
    recv_msg(SSLBool, Sock, 0),
    %%主题
    send_msg(SSLBool, Sock, "SUBJECT:" ++ EMail#email.subject ++ "\r\n"),
    send_msg(SSLBool, Sock, "MIME-VERSION: 1.0\r\n"),
    send_msg(SSLBool, Sock, "CONTENT-TYPE: multipart/mixed; BOUNDARY=\"#BOUNDARY#\"\r\n"),%设置边界标识
    send_msg(SSLBool, Sock, "\r\n"),
    %%内容
    send_msg(SSLBool, Sock, "--#BOUNDARY#\r\n"),
    send_msg(SSLBool, Sock, "Content-Type: text/plain;charset=utf-8\r\n"),
    send_msg(SSLBool, Sock, "Content-Transfer-Encoding:7bit\r\n\r\n"), %默认即为7bit
    send_msg(SSLBool, Sock, EMail#email.content ++ "\r\n"),
    recv_msg(SSLBool, Sock, 0),
    %%附件
    send_email_attachment(SSLBool, "application/msword", EMail#email.attachment, Sock),
    %%退出   最后以.结束
    send_msg(SSLBool, Sock, "\r\n.\r\n"),
    recv_msg(SSLBool, Sock, 0),
    send_msg(SSLBool, Sock, "QUIT\r\n"),
    recv_msg(SSLBool, Sock, 0).


%%%===================LOCAL FUNCTIONS==================
%% ----------------------------------------------------
%% @doc
%%      发送附件
%% @end
%% ----------------------------------------------------
%% send email other type
send_email_attachment(_SSLBool, _Type, [], _Sock) ->
    nothing_to_return;
send_email_attachment(SSLBool, Type, [FilePath | Rest], Sock) ->
    %%发送附件头部部分
    send_msg(SSLBool, Sock, "--#BOUNDARY#\r\n"),
    send_msg(SSLBool, Sock, "CONTENT-TYPE: "),
    send_msg(SSLBool, Sock, Type),
    send_msg(SSLBool, Sock, "; NAME="),
    send_msg(SSLBool, Sock, filename:basename(FilePath)),
    send_msg(SSLBool, Sock, "\r\n"),
    send_msg(SSLBool, Sock, "CONTENT-TRANSFER-ENCODING: base64\r\n"),
    send_msg(SSLBool, Sock, "\r\n"),
    %%发送附件内容  用二进制方式读取附件文件内容并转为base64格式
    {ok, File} = file:open(FilePath, [binary, read]),
    send_file_to_email(SSLBool, Sock, File),
    ok = file:close(File),
    send_msg(SSLBool, Sock, "\r\n\r\n"),
    send_email_attachment(SSLBool, Type, Rest, Sock).


%% ----------------------------------------------------
%% @doc
%%   用二进制方式读取附件文件内容并转为base64格式,并发送到邮件服务器
%% @end
%% ----------------------------------------------------
send_file_to_email(SSLBool, Sock, File) ->
    case file:read(File, 1024) of
        {ok, Data} ->
            ok = send(SSLBool, Sock, base64:encode(Data)),
            send_file_to_email(SSLBool, Sock, File);
        eof -> eof;
        {error, Reason} -> io:format("read failed: ~p~n", [Reason])
    end.
%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
send_msg(SSLBool, Sock, Data) ->
    Data1 = if
        is_list(Data) ->
            unicode:characters_to_binary(Data);
        true ->
            Data
    end,
    ?FMT(?SENDFMT, [Data1]),
    send(SSLBool, Sock, Data1).

recv_msg(true, Sock, Options) ->
    Data = ssl:recv(Sock, Options),
    ?FMT(?RECVFMT, [Data]);
recv_msg(false, Sock, Options) ->
    Data = gen_tcp:recv(Sock, Options),
    ?FMT(?RECVFMT, [Data]).

send(SSLBool, Sock, Data) ->
    if
        SSLBool ->
            ssl:send(Sock, Data);
        true ->
            gen_tcp:send(Sock, Data)
    end.


