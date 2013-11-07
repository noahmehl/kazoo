-ifndef(HANGUPS_HRL).

-include_lib("whistle/include/wh_log.hrl").
-include_lib("whistle/include/wh_types.hrl").
-include_lib("whistle/include/wh_databases.hrl").

-define(IGNORE, [<<"NO_ANSWER">>
                 ,<<"USER_BUSY">>
                 ,<<"NO_USER_RESPONSE">>
                 ,<<"LOSE_RACE">>
                 ,<<"ATTENDED_TRANSFER">>
                 ,<<"ORIGINATOR_CANCEL">>
                 ,<<"NORMAL_CLEARING">>
                 ,<<"ALLOTTED_TIMEOUT">>
                ]).

-define(HANGUPS_HRL, 'true').
-endif.
