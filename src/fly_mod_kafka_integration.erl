-module(fly_mod_kafka_integration).
-author("Venkatesh").

%% Every ejabberd module implements the gen_mod behavior
%% The gen_mod behavior requires two functions: start/2 and stop/1
-behaviour(gen_mod).
-define(EJABBERD_DEBUG, true).
-define(PROCNAME, fly_mod_kafka_integration).
%% public methods for this module
-export([start/2, stop/1, depends/2,mod_options/1, mod_opt_type/1, send_to_kafka/2,delivery_report/2]).

%% included for writing to ejabberd log file
-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").


%% Start the module and set up Kafka connection
start(Host, Opts) ->
    % Initialize Kafka producer/consumer with brod or other libraries
    erlkaf:start(),
    KafKaHost = gen_mod:get_module_opt(Host, ?PROCNAME, kafka_host),
    KafkaPort = gen_mod:get_module_opt(Host, ?PROCNAME, kafka_port),
    ConnectionString = list_to_binary(binary_to_list(KafKaHost) ++ ":" ++ binary_to_list(KafkaPort)),
    ProducerConfig = [
        {bootstrap_servers, ConnectionString},
        {delivery_report_only_error, false},
        {delivery_report_callback, ?MODULE}
    ],
    
    ok = erlkaf:create_producer(client_producer, ProducerConfig),
    ok.

%% Stop the module and close connections
stop(Host) ->
        erlkaf:stop(),
    ok.

%% Sample hook to publish XMPP messages to Kafka
send_to_kafka(KafkaTopic, Msg) ->
   
%  KafkaTopic is an topic_id/quename
 ok = erlkaf:produce(client_producer, KafkaTopic, <<"content">>, Msg).


delivery_report(DeliveryStatus, Message) ->
    io:format("received delivery report: ~p ~n", [{DeliveryStatus, Message}]),
    ok.

depends(_, _) ->
  [].

mod_options(_Host) ->
  [{kafka_host, undefined},
    {kafka_port, undefined}].

mod_opt_type(kafka_host) -> fun iolist_to_binary/1;
mod_opt_type(kafka_port) -> fun iolist_to_binary/1;
mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
mod_opt_type(db_type) ->
  fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(_) ->
  [db_type, iqdisc, kafka_host, kafka_port].

