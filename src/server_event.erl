-module(server_event).
-author("yhw").

-behaviour(gen_server).

%% API
-export([start_link/0, inform/3]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(INTERVAL, 1000).%超时检查间隔时间
-record(state, {ets, run_list}).

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    erlang:send_after(?INTERVAL, self(), 'handle_time_out'),
    {ok, #state{ets = server_event, run_list = []}}.

handle_call({inform, Src, Mark, Args}, From, #state{ets = Ets, run_list = L} = State) ->
    case config_lib:get(Ets, {Src, Mark}) of
        {_, {M, F, A}, 0} ->%同步事件
            spawn(fun() ->
                Reply = run(M, F, A, Src, Mark, Args),
                gen_server:reply(From, Reply) end),
            {noreply, ok, State};
        {_, {M, F, A}, TimeOut} ->%异步事件
            MS = time_lib:now_millisecond(),
            {Pid, Ref} = spawn_monitor(fun() -> run(M, F, A, Src, Mark, Args) end),
            EndTime = MS + TimeOut,
            NL = [{{Pid, Ref}, EndTime} | L],
            {reply, ok, State#state{run_list = NL}};
        _ ->
            {reply, ok, State}
    end;
handle_call(_Request, _From, State) ->
    {reply, ok, State}.


handle_cast(_Request, State) ->
    {noreply, State}.


handle_info('handle_time_out', #state{run_list = L} = State) ->
    NL = if
        length(L) =:= 0 ->
            [];
        true ->
            handle_run_list(L)
    end,
    erlang:send_after(?INTERVAL, self(), 'handle_time_out'),
    {noreply, State#state{run_list = NL}};
handle_info({'DOWN', Ref, process, Pid, Reason}, #state{run_list = L} = State) ->
    L1 = lists:keydelete({Pid, Ref}, 1, L),
    case Reason of
        'normal' ->
            ok;
        _ ->
            error_logger:error_msg("Error reading ~s's file info: ~p~n", [Reason])
    end,
    {noreply, State#state{run_list = L1}};
handle_info(_Info, State) ->
    {noreply, State}.


terminate(_Reason, _State) ->
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
inform(Src, Mark, Args) ->
    case config_lib:get(?MODULE, {Src, Mark}) of
        {_, _, _TimeOut} ->
            gen_server:call(?MODULE, {inform, Src, Mark, Args});
        _ ->
            ok
    end.



run(M, F, A, Src, Mark, Args) ->
    try
        M:F(A, Src, Mark, Args),
        ok
    catch
        _E1: E2 ->
            Stack = erlang:get_stacktrace(),
            log4erl:log(info, "~p~n", [{E2, {M, F, A}, Stack}]),
            {error, {E2, {M, F, A}, Stack}}
    end.

handle_run_list(L) ->
    SortFun = fun({_, A}, {_, B}) -> A > B end,
    L1 = lists:sort(SortFun, L),
    NowMS = time_lib:now_millisecond(),
    handle_run_list_(L1, NowMS).

handle_run_list_([{_Key, TimeOut} | _T] = L, NowMS) when NowMS < TimeOut ->
    L;
handle_run_list_([{Key, _TimeOut} | T], NowMS) ->
    {Pid, _Ref} = Key,
    erlang:exit(Pid, kill),
    handle_run_list_(T, NowMS).