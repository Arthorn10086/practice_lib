-module(file_monitor).
-author("yhw").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(ETS_REOLAD_TIME, 'file_monitor').
-define(REOLAD_INTERVAL, 20000).
-define(PROJECT, zero).
-include_lib("kernel/include/file.hrl").
-record(state, {
    file_update_time
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    %%创建文件更新ets表
    Ets = ets:new(?ETS_REOLAD_TIME, [named_table, protected, set]),
    %%启动定时器
    erlang:start_timer(?REOLAD_INTERVAL, self(), {refresh}),
    {ok, #state{file_update_time = Ets}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
handle_call({'init_cfg', AllCFG}, _From, #state{file_update_time = Ets} = State) ->
    %%config会在init的时候初始化所有配置，记录加载的所有配置文件的修改时间和文件包含的配置的Key
    after_update_cfg(Ets, AllCFG),
    {reply, true, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({timeout, _TimerRef, {refresh}}, State) ->
    do_refresh_config(State),
    erlang:start_timer(?REOLAD_INTERVAL, self(), {refresh}),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%配置文件更新
do_refresh_config(#state{file_update_time = Ets}) ->
%%拿到所有配置文件
    AllCFGFile = filelib:wildcard("./config/*" ++ ".cfg"),
    F = fun(File, R) ->
        case file:read_file_info(File) of
            {ok, #file_info{mtime = MT}} ->
                case ets:lookup(Ets, File) of
                    [] ->
                        [File | R];
                    [{File, _CfgL, OldTime} | _] ->
                        if
                            OldTime < MT ->
                                [File | R];
                            true ->
                                R
                        end;
                    _ -> R
                end;
            {error, enoent} ->
                R;
            {error, Reason} ->
                error_logger:error_msg("Error reading ~s's file info: ~p~n", [File, Reason]),
                R
        end
    end,
    LoadFiles = lists:foldl(F, [], AllCFGFile),
    %%通知config,返回配置文件中所有的配置项的key
    case gen_server:call('config_lib', {'load_cfg', LoadFiles}) of
        ignore ->
            ok;
        AllReply ->
            after_update_cfg(Ets, AllReply),
            if
                length(LoadFiles) =:= 0 ->
                    ok;
                true ->
                    io:format("-------------------Hot Update Over------------------------~n~p~n", [LoadFiles])
            end
    end.


%%修改配置文件的信息之后处理
after_update_cfg(Ets, AllCFG) ->
    F = fun({File, CfgList}) ->
        case file:read_file_info(File) of
            {ok, #file_info{mtime = MT}} ->
                case ets:lookup(Ets, File) of
                    [] ->
                        ok;
                    [{File, OldCfgList, _} | _] ->
                        %%检验Key，处理本次修改后已删除的旧配置
                        update_delete(CfgList, OldCfgList)
                end,
                Bool = lists:all(fun({_, L}) -> L =:= [] end, CfgList),
                if
                    Bool ->
                        ok;
                    true ->
                        ets:insert(Ets, {File, CfgList, MT})
                end;
            {error, enoent} ->
                ok;
            {error, Reason} ->
                error_logger:error_msg("Error reading ~s's file info: ~p~n", [File, Reason])
        end
    end,
    lists:foreach(F, AllCFG).

%%file_monitor中保存了每个文件中的配置key值，对比，如果更新后有删除的，通知cfg删除
update_delete(NewCfgList, OldCfgList) ->
    %%处理配置表
    F = fun({T, Keys}) ->
        case lists:keyfind(T, 1, list_lib:get_value('config', 1, NewCfgList, [])) of
            false ->
                lists:foreach(fun(Key) -> config_lib:delete(T, Key) end, Keys),
                case ets:info(T, size) =:= 0 of%%如果是文件配置表中没有数据了，就删除表
                    'true' ->
                        config_lib:delete(T);
                    _ ->
                        ok
                end;
            {T, NewKeys} ->
                DKeys = Keys--NewKeys,
                lists:foreach(fun(Key) -> config_lib:delete(T, Key) end, DKeys)
        end
    end,
    lists:foreach(F, list_lib:get_value('config', 1, OldCfgList, [])),
    %%tcp http protocol
    lists:foreach(fun(Type) ->
        NProL = list_lib:get_value(Type, 1, NewCfgList, []),
        %% 处理通讯协议
        ProF = fun(Pro) ->
            case lists:member(Pro, NProL) of
                true ->
                    ok;
                false ->
                    config_lib:delete(Type, Pro)
            end
        end,
        lists:foreach(ProF, list_lib:get_value(Type, 1, OldCfgList, []))
    end, ['tcp_protocol', 'http_protocol']),
    %%event timer
    lists:foreach(fun(Type) ->
        NProL = list_lib:get_value(Type, 1, NewCfgList, []),
        %% 处理通讯协议
        ProF = fun(CFG) ->
            case lists:member(CFG, NProL) of
                true ->
                    ok;
                false ->
                    config_lib:delete(Type, CFG)
            end
        end,
        lists:foreach(ProF, list_lib:get_value(Type, 1, OldCfgList, []))
    end, ['server_event', 'server_timer']).