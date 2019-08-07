-module(server_event).
-author("yhw").

-behaviour(gen_server).

%% API
-export([start_link/0, inform/3, set/3, delete/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).
-define(INTERVAL, 1000).%超时检查间隔时间
-define(TIMEOUT, 5000).
-record(state, {ets, run_list}).

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

inform(Src, Mark, Args) ->
    case config_lib:get(?MODULE, {Src, Mark}) of
        {_, {M, F, A}, 0} ->%%同步事件
            run(M, F, A, Src, Mark, Args),
            ok;
        {_, {M, F, A}, TimeOut} ->%%异步事件
            gen_server:call(?MODULE, {inform, Src, Mark, Args, {M, F, A}, TimeOut});
        _ ->
            ok
    end.
set(Ref, MFA, TimeInfo) ->
    gen_server:call(?MODULE, {'set', Ref, MFA, TimeInfo}, ?TIMEOUT).
delete(Ref) ->
    gen_server:call(?MODULE, {'delete', Ref}, ?TIMEOUT).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    Ets = ets:new(?MODULE, [named_table, protected, set]),
    erlang:send_after(?INTERVAL, self(), 'handle_time_out'),
    {ok, #state{ets = Ets, run_list = []}}.

handle_call({inform, Src, Mark, Args, {M, F, A}, TimeOut}, _From, #state{run_list = L} = State) ->
    MS = time_lib:now_millisecond(),
    {Pid, Ref} = spawn_monitor(fun() -> run(M, F, A, Src, Mark, Args) end),
    EndTime = MS + TimeOut,
    NL = [{{Pid, Ref}, Mark, Args, {M, F, A}, EndTime} | L],
    {reply, ok, State#state{run_list = NL}};
handle_call({'set', Ref, MFA, TimeInfo}, _From, #state{ets = Ets} = State) ->
    ets:insert(Ets, {Ref, MFA, TimeInfo}),
    {reply, ok, State};
handle_call({'delete', Ref}, _From, #state{ets = Ets} = State) ->
    ets:delete(Ets, Ref),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.


handle_cast(_Request, State) ->
    {noreply, State}.


handle_info('handle_time_out', #state{run_list = L} = State) ->
    NL = handle_run_list(L),
    erlang:send_after(?INTERVAL, self(), 'handle_time_out'),
    {noreply, State#state{run_list = NL}};
handle_info({'DOWN', Ref, process, Pid, Reason}, #state{run_list = L} = State) ->
    L1 = lists:keydelete({Pid, Ref}, 1, L),
    case Reason of
        'normal' ->
            ok;
        'time_out'->
            ok;
        _ ->
            lager:log(error, Pid, "~p~n", [{Ref, Reason}])
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
run(M, F, A, Src, Mark, Args) ->
    try
        M:F(A, Src, Mark, Args),
        ok
    catch
        E1: E2 ->
            Stack = erlang:get_stacktrace(),
            lager:log(error, self(), "~p~n", [{E1, E2, {M, F, A}, Stack}]),
            {error, {E2, {M, F, A}, Stack}}
    end.
handle_run_list([]) ->
    [];
handle_run_list(L) ->
    SortFun = fun({_, _, _, _, A}, {_, _, _, _, B}) -> A > B end,
    L1 = lists:sort(SortFun, L),
    NowMS = time_lib:now_millisecond(),
    handle_run_list_(L1, NowMS).
handle_run_list_([], _) ->
    [];
handle_run_list_([{_Key, _, _, _, TimeOut} | _T] = L, NowMS) when NowMS < TimeOut ->
    L;
handle_run_list_([{Key, Mark, Args, MFA, _TimeOut} | T], NowMS) ->
    {Pid, _Ref} = Key,
    erlang:exit(Pid, 'time_out'),
    log_lib:error(Pid, [{Mark, xmerl_ucs:to_utf8(Args), MFA}]),
    handle_run_list_(T, NowMS).