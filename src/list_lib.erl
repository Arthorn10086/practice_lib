-module(list_lib).

%%%=======================STATEMENT====================
-description("list_lib").
-author("yhw").

%%%=======================EXPORT=======================
-export([merge_kv/2, get_value/4, foreach/3]).

%%%=======================INCLUDE======================

%%%=======================DEFINE======================

%%%=======================RECORD=======================

%%%=======================TYPE=========================
%%-type my_type() :: atom() | integer().


%%%=================EXPORTED FUNCTIONS=================
%% ----------------------------------------------------
%% @doc  
%%        合并
%% @end
%% ----------------------------------------------------
merge_kv([], R) ->
    R;
merge_kv([{_T, []} | Rest], R) ->
    merge_kv(Rest, R);
merge_kv([{T, Keys} | Rest], R) ->
    case lists:keyfind(T, 1, R) of
        false ->
            merge_kv(Rest, [{T, Keys} | R]);
        {T, OldKeys} ->
            merge_kv(Rest, lists:keyreplace(T, 1, R, {T, OldKeys ++ Keys}))
    end.
%% ----------------------------------------------------
%% @doc
%%        带默认值的keyfind
%% @end
%% ----------------------------------------------------
get_value(Key, N, List, Default) ->
    case lists:keyfind(Key, N, List) of
        false ->
            Default;
        T ->
            element(2, T)
    end.
%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
foreach(F, Args, [H | T]) ->
    case F(Args, H) of
        {break, A} ->
            A;
        {ok, A} ->
            foreach(F, A, T);
        A ->
            foreach(F, A, T)
    end;
foreach(_F, Args, []) ->
    Args.


%%%===================LOCAL FUNCTIONS==================
%% ----------------------------------------------------
%% @doc  
%%  
%% @end
%% ----------------------------------------------------
