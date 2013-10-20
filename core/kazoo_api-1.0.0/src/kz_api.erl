%%%-------------------------------------------------------------------
%%% @copyright (C) 2013, 2600Hz
%%% @doc
%%% Handles authentication requests, responses, queue bindings
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kz_api).

-export([build_message/1
         ,find_schema/1
         ,init_schemas/0
        ]).

-include("kazoo_api.hrl").

build_message(JObj) ->
    wh_json:encode(JObj).

find_schema(SchemaName) ->
    case wh_cache:fetch(SchemaName) of
        {'ok', _Schema}=OK -> OK;
        {'error', 'not_found'} ->
            case code:priv_dir('kazoo_api') of
                {'error', 'bad_name'} ->
                    lager:debug("kazoo_api/priv missing or not found"),
                    {'error', 'not_found'};
                Path ->
                    lager:debug("found ~s in ~s", [SchemaName, Path]),
                    import_schema(Path ++ ["/", SchemaName, ".json"])
            end
    end.

import_schema(Path) when is_list(Path) ->
    import_schema(list_to_binary(Path));
import_schema(Path) ->
    SchemaName = filename:basename(Path, ".json"),

    {'ok', Bin} = file:read_file(Path),
    try wh_json:decode(Bin) of
        Schema ->
            MergedSchema = merge_defaults(Schema),
            lager:debug("caching ~s", [SchemaName]),
            wh_cache:store(SchemaName, MergedSchema),
            {'ok', MergedSchema}
    catch
        _E:_R ->
            lager:debug("failed to decode JSON: ~s: ~p", [_E, _R]),
            lager:debug("looked in ~s, found ~s", [Path, Bin]),
            {'error', 'not_found'}
    end.

-spec merge_defaults(wh_json:object()) -> wh_json:object().
merge_defaults(Schema) ->
    Properties = wh_json:get_value(<<"properties">>, Schema, wh_json:new()),
    MergedProperties = wh_json:merge_jobjs(Properties, ?DEFAULT_HEADERS_SCHEMA),
    wh_json:set_value(<<"properties">>, MergedProperties, Schema).

init_schemas() ->
    case code:priv_dir('kazoo_api') of
        {'error', 'bad_name'} ->
            lager:debug("kazoo_api/priv missing or not found"),
            {'error', 'not_found'};
        Path ->
            lager:debug("checking ~s for files", [Path]),
            case filelib:wildcard(Path ++ "/*.json") of
                [] ->
                    lager:debug("found no json files in ~s", [Path]),
                    {'error', 'not_found'};
                JSONFiles ->
                    [init_schema(JSONFile) || JSONFile <- JSONFiles],
                    'ok'
            end
    end.

init_schema(JSONFile) ->
    case import_schema(JSONFile) of
        {'ok', _Schema} ->
            lager:debug("loaded ~s sucessfully", [JSONFile]);
        {'error', _E} ->
            lager:debug("failed to load ~s: ~p", [JSONFile, _E]),
            {'error', 'not_found'}
    end.
