-module(server_timer).
-author("yhw").

-behaviour(gen_server).

%% API
-export([start_link/0, set/3, delete/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(INTERVAL, 1000).%定时器执行间隔时间
-define(RUNING, 1).%执行中
-define(WAITING, 0).%未执行
-define(TIMEOUT, 5000).
-record(state, {ets, run_list, last_time}).

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
set(Ref, MFA, TimeInfo) ->
    gen_server:call(?MODULE, {'set', Ref, MFA, TimeInfo}, ?TIMEOUT).
delete(Ref) ->
    gen_server:call(?MODULE, {'delete', Ref}, ?TIMEOUT).

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
    ets:new(?MODULE, [named_table, protected, set]),
    {ok, #state{ets = ?MODULE, run_list = [], last_time = time_lib:now_second()}, ?INTERVAL}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
handle_call({'set', Ref, MFA, TimeInfo}, _From, #state{ets = Ets} = State) ->
    case ets:lookup(Ets, Ref) of
        [] ->
            ets:insert(Ets, {Ref, MFA, TimeInfo, 0, ?WAITING});
        [{_, _, _, NextTime, Flag}] ->
            ets:insert(Ets, {Ref, MFA, TimeInfo, NextTime, Flag})
    end,
    {reply, ok, State};
handle_call({'delete', Ref}, _From, #state{ets = Ets} = State) ->
    ets:delete(Ets, Ref),
    {reply, ok, State};
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
handle_info(timeout, #state{ets = Ets, run_list = RunL} = State) ->
    Now = time_lib:now_second(),
    NowM = time_lib:now_millisecond(),
    time_out_handle(RunL, NowM),
    {_, NRunL} = timer_run(Ets, RunL, NowM),
    erlang:send_after(?INTERVAL, self(), timeout),
    {noreply, State#state{run_list = NRunL, last_time = Now}};
handle_info({'DOWN', Ref, process, Pid, Reason}, #state{ets = Ets, run_list = L} = State) ->
    MS = time_lib:now_millisecond(),
    {value, Info, NRunL} = lists:keytake(Pid, 1, L),
    case Reason of
        'normal' ->
            ok;
        _ ->
            log4erl:log('info', "~p~n", [{Pid, Ref, Reason}])
    end,
    {Pid, Ref, _, _} = Info,
    case ets:lookup(Ets, Ref) of
        [] ->
            ok;
        [{Ref, MFA, TimeInfo, _, _}] ->
            {Interval, _} = TimeInfo,
            ets:insert(Ets, {Ref, MFA, TimeInfo, MS + Interval, ?WAITING}),
            ok
    end,
    {noreply, State#state{run_list = NRunL}};
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
%%执行
timer_run(Ets, RunL, NowM) ->
    F = fun({Ref, MFA, TimeInfo, NextTime, Flag}, {MS, RunList} = Acc) ->
        Bool = Flag =:= ?RUNING orelse lists:keyfind(Ref, 2, RunList) =/= false,
        if
            Bool ->
                Acc;
            true ->
                if
                    MS >= NextTime ->
                        {_, OutTime} = TimeInfo,
                        {Pid, _PRef} = spawn_monitor(fun() ->
                            try
                                {M, F, A} = MFA,
                                M:F(A, Ref, MS)
                            catch
                                E1: E2 ->
                                    log4erl:log(info, "~p~n", [{E1, E2, erlang:get_stacktrace()}])
                            end
                        end),
                        ets:insert(Ets, {Ref, MFA, TimeInfo, NextTime, ?RUNING}),
                        {MS, [{Pid, Ref, MFA, MS + OutTime} | RunList]};
                    true ->
                        Acc
                end
        end
    end,
    foldl(F, {NowM, RunL}, Ets).


%%遍历Ets表
foldl(F, Accu, Ets) ->
    First = ets:first(Ets),
    do_foldl(F, Accu, First, Ets).

do_foldl(F, Accu0, Key, T) ->
    case Key of
        '$end_of_table' ->
            Accu0;
        _ ->
            case ets:lookup(T, Key) of
                [TimerInfo] ->
                    Acc = F(TimerInfo, Accu0),
                    do_foldl(F, Acc, ets:next(T, Key), T);
                [] ->
                    Accu0
            end
    end.


%%超时处理
time_out_handle(List, Time) ->
    SortFun = fun({_, _, _, A}, {_, _, _, B}) -> A > B end,
    L1 = lists:sort(SortFun, List),
    list_lib:foreach(fun({Pid, _Ref, _MFA, OutTime}) ->
        if
            OutTime =< Time ->
                erlang:exit(Pid, 'time_out'),
                ok;
            true ->
                {break, ok}
        end
    end, ok, L1).