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

set(TableName, Info) ->
    case ets:info(TableName) of
        undefined -> gen_server:call(?SERVER, {'create', TableName, [Info], ?DEFAULT_OPTIONS}, ?TIMEOUT);
        _ ->
            gen_server:call(?SERVER, {'update', TableName, Info}, ?TIMEOUT)
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
handle_call({'update', TableName, Info}, _From, State) ->
    KeyPos = ets:info(TableName, keypos),
    Key = element(KeyPos, Info),
    [OldV] = ets:lookup(TableName, Key),
    ets:insert(TableName, Info),
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
