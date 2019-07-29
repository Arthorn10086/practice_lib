-module(config_lib).
-author("yhw").

-behaviour(gen_server).

%% API
-export([start_link/0, set/2, set/3, get/1, get/2, get_list/0, delete/1, delete/2]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(TIMEOUT, 7000).
-define(DEFAULT_OPTIONS, [named_table, protected, set]).


%%%===================================================================
%%% API
%%%===================================================================
%%设置配置
set(TableName, KVList, Options) ->
    case ets:info(TableName) of
        undefined ->
            gen_server:call(?SERVER, {'create', TableName, KVList, Options ++ ?DEFAULT_OPTIONS}, ?TIMEOUT);
        _ ->
            gen_server:call(?SERVER, {'batch_update', TableName, KVList}, ?TIMEOUT)
    end.

set(TableName, {K, V}) ->
    case ets:info(TableName) of
        undefined -> gen_server:call(?SERVER, {'create', TableName, [{K, V}], ?DEFAULT_OPTIONS}, ?TIMEOUT);
        _ ->
            gen_server:call(?SERVER, {'update', TableName, {K, V}}, ?TIMEOUT)
    end.

%%获取配置
get(TableName) ->
    case ets:info(TableName) of
        undefined -> none;
        _ ->
            ets:tab2list(TableName)
    end.
get(TableName, Key) ->
    case ets:info(TableName) of
        undefined -> none;
        _ ->
            case ets:lookup(TableName, Key) of
                [] ->
                    none;
                [V] ->
                    V
            end
    end.
%%删除配置表
delete(TableName) ->
    gen_server:cast(?SERVER, {delete, TableName}).
delete(TableName, Key) ->
    gen_server:call(?SERVER, {delete, TableName, Key}, ?TIMEOUT).

get_list() ->
    L = ets:tab2list(?MODULE),
    [T || {T} <- L].
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([]) ->
    Ets = ets:new(?MODULE, [named_table, protected, set]),
    %%初始化所有配置表进内存
    AllCfg = init_cfg(),
    %%通知文件管理进程更新文件刷新表
    true = gen_server:call('file_monitor', {'init_cfg', AllCfg}),
    {ok, Ets, hibernate}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
%%删除表中的值
handle_call({'delete', TableName, Key}, _From, State) ->
    Reply = try
        [OldV] = ets:lookup(TableName, Key),
        ets:delete(TableName, Key),
        {ok, OldV}
    catch
        _:_ ->
            none
    end,
    {reply, Reply, State, hibernate};
%%修改
handle_call({'update', TableName, {K, V}}, _From, State) ->
    [OldV] = ets:lookup(TableName, K),
    ets:insert(TableName, {K, V}),
    {reply, {ok, OldV}, State, hibernate};
%%批量修改
handle_call({'batch_update', TableName, KVL}, _From, State) ->
    F = fun(Data) ->
        ets:insert(TableName, Data)
    end,
    lists:foreach(F, KVL),
    {reply, ok, State, hibernate};
%%创建新表并设置值
handle_call({'create', TableName, KVL, Options}, _From, State) ->
    Ets = ets:new(TableName, Options),
    F = fun(Data) ->
        ets:insert(Ets, Data)
    end,
    lists:foreach(F, KVL),
    ets:insert(State, {TableName}),
    {reply, ok, State, hibernate};
%%解析加载配置文件
handle_call({'load_cfg', Files}, _From, State) ->
    F = fun(R, File) ->
        try
            {ok, DataL} = file:consult(File),
            Reply = lists:foldl(fun handle_/2, [], DataL),
            [{File, Reply} | R]
        catch
            E1:E2 ->
                error_logger:error_msg("Error load_file : ~p~p~n~p~n", [E1, E2, erlang:get_stacktrace()]),
                {break, ignore}
        end
    end,
    Reply = list_lib:foreach(F, [], Files),
    {reply, Reply, State, hibernate};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
%%删表
handle_cast({'delete', TableName}, Ets) ->
    ets:delete(TableName),
    ets:delete(Ets, TableName),
    {noreply, Ets, hibernate};
handle_cast(_Request, State) ->
    {noreply, State}.


handle_info(_Info, State) ->
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
init_cfg() ->
    %%拿到所有配置文件
    FileL = filelib:wildcard("./config/*" ++ ".cfg"),
    AllCFGFile = FileL,
    F = fun(File, R) ->
        {ok, DataL} = file:consult(File),
        Reply = lists:foldl(fun handle_/2, [], DataL),
        [{File, Reply} | R]
    end,
    lists:foldl(F, [], AllCFGFile).


%%配置表
handle_({'config', {TableName, KVList, Options}}, Reply) ->
    case ets:lookup(?MODULE, TableName) of
        [] ->
            Ets = ets:new(TableName, Options ++ ?DEFAULT_OPTIONS),
            ets:insert(?MODULE, {TableName}),
            [ets:insert(Ets, KV) || KV <- KVList];
        _ ->
            [ets:insert(TableName, KV) || KV <- KVList]
    end,
    KeyPos = ets:info(TableName, 'keypos'),
    CFGL = list_lib:get_value('config', 1, Reply, []),
    NCFGL = [{TableName, [element(KeyPos, Item) || Item <- KVList]} | CFGL],
    NCFGL1 = [{T, Keys} || {T, Keys} <- list_lib:merge_kv(NCFGL, []), Keys =/= []],
    NReply = lists:keystore('config', 1, Reply, {'config', NCFGL1}),
    NReply;
%%通讯协议
handle_({Type, {Ref, MFAList, LogFun, TimeOut}}, Reply) when Type =:= 'tcp_protocol' orelse Type =:= 'http_protocol' ->
    case ets:lookup(?MODULE, Type) of
        [] ->
            Ets = ets:new(Type, ?DEFAULT_OPTIONS),
            ets:insert(?MODULE, {Type}),
            ets:insert_new(Ets, {Ref, MFAList, LogFun, TimeOut});
        _ ->
            ets:insert_new(Type, {Ref, MFAList, LogFun, TimeOut})
    end,
    ProL = list_lib:get_value(Type, 1, Reply, []),
    NReply = lists:keystore(Type, 1, Reply, {Type, [Ref | ProL]}),
    NReply;
handle_({Type, {Ref, MFA, TimeInfo}}, Reply) when Type =:= 'server_event' orelse Type =:= 'server_timer' ->
    case ets:lookup(?MODULE, Type) of
        [] ->
            Ets = ets:new(Type, ?DEFAULT_OPTIONS),
            ets:insert(?MODULE, {Type}),
            ets:insert_new(Ets, {Ref, MFA, TimeInfo});
        _ ->
            ets:insert_new(Type, {Ref, MFA, TimeInfo})
    end,
    ProL = list_lib:get_value(Type, 1, Reply, []),
    NReply = lists:keystore(Type, 1, Reply, {Type, [Ref | ProL]}),
    NReply;
handle_(_Data, Reply) ->
    Reply.
