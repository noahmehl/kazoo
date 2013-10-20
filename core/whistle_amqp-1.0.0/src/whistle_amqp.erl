%%%-------------------------------------------------------------------
%%% @copyright (C) 2012-2013, 2600Hz, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%-------------------------------------------------------------------
-module(whistle_amqp).

-export([start_link/0, start/0]).
-export([stop/0]).

-include("amqp_util.hrl").

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Starts the app for inclusion in a supervisor tree
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> startlink_ret().
start_link() ->
    _ = start_deps(),
    wh_amqp_sup:start_link().

-spec start() -> 'ok' | {'error', _}.
start() ->
    _ = start_deps(),
    application:start('whistle_amqp', 'permanent').

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Stop the app
%% @end
%%--------------------------------------------------------------------
-spec stop() -> 'ok'.
stop() ->
    application:stop('whistle_amqp').

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Ensures that all dependencies for this app are already running
%% @end
%%--------------------------------------------------------------------
-spec start_deps() -> 'ok'.
start_deps() ->
    _ = [wh_util:ensure_started(App) || App <- [sasl, amqp_client]],
    'ok'.
