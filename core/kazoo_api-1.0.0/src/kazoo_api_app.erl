-module(kazoo_api_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    kazoo_api:start_link().

stop(_State) ->
    kazoo_api:stop().
