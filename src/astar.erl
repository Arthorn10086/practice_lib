-module(astar).

%%%=======================STATEMENT====================
-description("astar").
-author("yhw").

%%%=======================EXPORT=======================
-export([find/3]).

%%%=======================RECORD=======================
-record(map_node, {
    point :: {integer(), integer()},%{x,y}
    father = {-1, -1} :: {integer(), integer()},%父节点
    f = 0 :: float(),%起点到终点的最短路径长度    F=G+H
    g = 0 :: float(),%从起点到该节点的移动消耗
    h = 0 :: float()%该节点到终点的预计消耗
}
).

%%%=================EXPORTED FUNCTIONS=================
%% ----------------------------------------------------
%% @doc
%%      查找路径
%% @end
%% ----------------------------------------------------
find(MapType, Start, End) ->
    Bool = map:check_point_barrier(End, MapType),
    if
        Bool ->
            "unable_to_reach";
        true ->
            {EndX, EndY} = map:int_xy(End),
            put('end_point', {EndX, EndY}),
            StartNode = #map_node{point = map:int_xy(Start)},
            CloseList = [],
            OpenList = [StartNode],
            start_find(OpenList, CloseList, MapType)
    end.

%%%===================LOCAL FUNCTIONS==================
%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
start_find([], _, _) -> "not_find";
start_find(OpenList, CloseList, MapType) ->
    %%在开放列表里面找到最佳节点
    {NextNode, OpenListT} = find_next_node(OpenList),
    case NextNode#map_node.point =:= get('end_point') of
        true ->
            make_path(NextNode, []);
        false ->
            %%更新closelist
            NewCloseList = [NextNode | CloseList],
            put(NextNode#map_node.point, NextNode),
            %%更新openlist
            NewOpenList = update_open_list(OpenListT, NewCloseList, NextNode, MapType),
            start_find(NewOpenList, NewCloseList, MapType)
    end.

%% ----------------------------------------------------
%% @doc
%%  更新open_list
%% @end
%% ----------------------------------------------------
update_open_list(OpenList, NewCloseList, NextNode, MapType) ->
    %%找到周围的点
    Points = get_around_points(NextNode, MapType, NewCloseList),
    lists:foldl(fun(Point, Acc) ->
        NewNode = init_map_node(Point, NextNode),
        case lists:keytake(Point, #map_node.point, Acc) of
            {value, OldNode, List} ->%%如果在open_list,比较G值，如果小则替换，
                case OldNode#map_node.f > NewNode#map_node.f of
                    true ->
                        [NewNode | List];
                    false ->
                        Acc
                end;
            false -> %%如果不在open close list,计算fgh直接加入
                [NewNode | Acc]
        end
    end, OpenList, Points).

%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
find_next_node(OpenList) ->
    Index = find_next_node(max, 0, 1, OpenList),
    NextNode = lists:nth(Index, OpenList),
    NOpenList = lists:delete(NextNode, OpenList),
    {NextNode, NOpenList}.
find_next_node(_MinValue, MinIndex, _Index, []) ->
    MinIndex;
find_next_node(MinValue, MinIndex, Index, [H | T]) ->
    F = H#map_node.f,
    case F < MinValue of
        true ->
            find_next_node(F, Index, Index + 1, T);
        false ->
            find_next_node(MinValue, MinIndex, Index + 1, T)
    end.

%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
make_path(undefined, Path) ->
    {ok, Path};
make_path(Node, Path) ->
    Father = Node#map_node.father,
    Point = Node#map_node.point,
    FNode = get(Father),
    make_path(FNode, [map:xy_int(Point) | Path]).

%% ----------------------------------------------------
%% @doc
%%
%% @end
%% ----------------------------------------------------
init_map_node({X, Y}, NextNode) ->
    {X1, Y1} = NextNode#map_node.point,
    Consume = case X1 =:= X orelse Y1 =:= Y of
        true ->
            1;
        false ->
            1.414
    end,
    G = NextNode#map_node.g + Consume,
    H = diagonal(X, Y),
    #map_node{point = {X, Y}, father = {X1, Y1}, f = G + H, g = G, h = H}.

%% ----------------------------------------------------
%% @doc
%%      1.地图范围内 2.不是障碍物 3.不在closelist
%% @end
%% ----------------------------------------------------
get_around_points(NextNode, MapType, CloseList) ->
    {Min, Max} = map:territory(MapType),
    {X, Y} = NextNode#map_node.point,
    F = fun(I, J) ->
        Bool1 = {I, J} =/= {X, Y},
        Bool2 = I >= Min andalso I =< Max andalso J >= Min andalso J =< Max,
        Bool3 = not lists:keymember({I, J}, #map_node.point, CloseList),
        Bool4 = not map:check_point_barrier(map:xy_int(I, J), MapType),
        Bool1 andalso Bool2 andalso Bool3 andalso Bool4
    end,
    [{I1, I2} || I1 <- [X - 1, X, X + 1], I2 <- [Y - 1, Y, Y + 1], F(I1, I2)].

%% ----------------------------------------------------
%% @doc
%%      H算法
%% @end
%% ----------------------------------------------------
%%manhattan(X, Y) ->
%%    {EndX, EndY} = get('end_point'),
%%    erlang:abs(EndX - X) + erlang:abs(EndY - Y).
%%
%%euclid(X, Y) ->
%%    {EndX, EndY} = get('end_point'),
%%    math:sqrt(math:pow(EndX - X, 2) + math:pow(EndY - Y, 2)).

diagonal(X, Y) ->
    {EndX, EndY} = get('end_point'),
    Dx = abs(X - EndX),
    Dz = abs(Y - EndY),
    MinD = min(Dx, Dz),
    MinD * 1.414 + Dx + Dz - 2 * MinD.



