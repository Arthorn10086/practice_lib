-module(log_lib).

%%%=======================STATEMENT====================
-description("log_lib").
-author("yhw").

%%%=======================EXPORT=======================
-export([info/2, error/2]).

%%%=======================INCLUDE======================

%%%=======================DEFINE======================

%%%=======================RECORD=======================

%%%=======================TYPE=========================
%%-type my_type() :: atom() | integer().


%%%=================EXPORTED FUNCTIONS=================
%% ----------------------------------------------------
%% @doc  
%%        
%% @end
%% ----------------------------------------------------
info(Pid, Data) ->
    lager:log(info, Pid, "~p~n", Data),
    ok.
error(Pid, Data) ->
    lager:log(error, Pid, "~p~n", Data),
    ok.


%%%===================LOCAL FUNCTIONS==================
%% ----------------------------------------------------
%% @doc  
%%  
%% @end
%% ----------------------------------------------------
