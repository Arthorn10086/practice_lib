-module(map).

%%%=======================STATEMENT====================
-description("map").
-author("yhw").

%%%=======================EXPORT=======================
-compile(export_all).

%%%=================EXPORTED FUNCTIONS=================
%% ----------------------------------------------------
%% @doc
%%        检测障碍物
%% @end
%% ----------------------------------------------------
check_point_barrier(Point, MapType) ->
    MapInfo = get_map_info(MapType),
    case ets:lookup(MapInfo, Point) of
        [] ->
            false;
        [{Point, 1}] ->
            true;
        [{Point, _Type}] ->
            false
    end.

%% ----------------------------------------------------
%% @doc
%%      xy坐标方法
%% @end
%% ----------------------------------------------------
int_xy(Point) ->
    <<_Z:16, X:16, Y:16>> = <<Point:48>>,
    {X, Y}.
xy_int({X, Y}) ->
    xy_int(X, Y).
xy_int(X, Y) ->
    <<P:32>> = <<X:16, Y:16>>,
    P.

%% ----------------------------------------------------
%% @doc
%%        获取地图的疆域
%% @end
%% ----------------------------------------------------
territory(1) ->
    {1, 10};
territory(2) ->
    {1, 100}.

%%%===================LOCAL FUNCTIONS==================
%% ----------------------------------------------------
%% @doc
%%      获取地图类型对应点配置
%% @end
%% ----------------------------------------------------
get_map_info(MapType) ->
    list_to_atom("map_info" ++ integer_to_list(MapType)).

%%%===================TEST FUNCTIONS==================
%% ----------------------------------------------------
%% @doc
%%  随机生成地图
%% @end
%% ----------------------------------------------------
random_init_map(MapType) ->
    {Min, Max} = territory(MapType),
    Border = lists:seq(Min, Max),
    Ets = get_map_info(MapType),
    L3 = [{xy_int(X, Y), rand:uniform(2) - 1} || X <- Border, Y <- Border],
    catch ets:new(Ets, [named_table, public, set, {read_concurrency, true}]),
    ets:insert(Ets, L3),
    show_map(MapType, []).

%% ----------------------------------------------------
%% @doc
%%  打印地图路线
%% @end
%% ----------------------------------------------------
find(MapType, StartX, StartY, EndX, EndY) ->
    case astar:find(MapType, map:xy_int(StartX, StartY), map:xy_int(EndX, EndY)) of
        {ok, List} ->
            show_map(MapType, List);
        Err ->
            Err
    end.

%% ----------------------------------------------------
%% @doc
%%  查看所有障碍物
%% @end
%% ----------------------------------------------------
get_barrier(MapType) ->
    Ets = get_map_info(MapType),
    [int_xy(P) || {P, F} <- ets:tab2list(Ets), F =:= 1].

%% ----------------------------------------------------
%% @doc
%%  打印地图   @行动路线 *障碍 +空地
%% @end
%% ----------------------------------------------------
show_map(MapType, PathList) ->
    {Min, Max} = territory(MapType),
    Border = lists:seq(Min, Max),
    PointL = [begin
        [{Point, Flag}] = ets:lookup(get_map_info(MapType), xy_int(X, Y)),
        {Point, Flag}
    end || X <- Border, Y <- Border],
    {_, Last, L} = lists:foldl(fun({P, F}, {Index, Acc, R}) ->
        Bool = lists:member(P, PathList),
        S = if
            Bool ->
                $@;
            F =:= 1 ->
                $*;
            true ->
                $+
        end,
        if
            Index =:= Max ->
                {1, [S], [Acc | R]};
            true ->
                {Index + 1, [S | Acc], R}
        end
    end, {0, [], []}, PointL),
    [io:format(lists:reverse(LL) ++ "~n") || LL <- [Last | L]].

