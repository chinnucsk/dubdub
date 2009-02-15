%%%-------------------------------------------------------------------
%%% File    : db.erl
%%% Author  : Brad Anderson <brad@sankatygroup.com>
%%% Description : This module serves as a database process inside
%%% of a single node
%%%
%%% Created : 26 Oct 2008 by Brad Anderson <brad@sankatygroup.com>
%%%-------------------------------------------------------------------
-module(db).

-behaviour(gen_server).

%% -include_lib("eunit/include/eunit.hrl").

-define(SERVER, ?MODULE).

%% API
-export([start_link/2, insert/2, get_all/1, get_count/1, q/3, truncate/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).


%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link(Node, InstanceId) ->
  case gen_server:start_link(?SERVER, [InstanceId], []) of
    {ok, Pid} ->
      db_manager:register_db(Node, Pid);
    Msg ->
      io:format("~p~n", [Msg])
  end.

insert(Node, V) ->
  gen_server:call(Node, {insert, null, V}).  % TODO: generate key hashes


q(list, Filter, Reduce) ->
  gen_server:call(?SERVER, {q, list, Filter, Reduce});
q(match_spec, MatchSpec, Reduce) ->
  gen_server:call(?SERVER, {q, match_spec, MatchSpec, Reduce});
q(dict, Filter, Reduce) ->
  gen_server:call(?SERVER, {q, dict, Filter, Reduce}).


get_all(Node) ->
  gen_server:call(Node, {get_all}).


get_count(Node) ->
  gen_server:call(Node, {get_count}).


truncate(Node) ->
  gen_server:call(Node, {truncate}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([InstanceId]) ->
  process_flag(trap_exit, true),
  io:format("starting DB ~p...~n", [InstanceId]),
  {ok, []}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({insert, K, V}, _From, State) ->
  NewState = [{K,V} | State],
  {reply, {ok, insert}, NewState};

handle_call({q, list, Filter, _Reduce}, _From, State) ->
  Results = lists:filter(Filter, State),
  {reply, {ok, Results}, State};

handle_call({q, match_spec, MatchSpec, _Reduce}, _From, State) ->
  CompiledMatchSpec = ets:match_spec_compile(MatchSpec),
  Results = ets:match_spec_run(State, CompiledMatchSpec),
  {reply, {ok, Results}, State};

handle_call({q, dict, Filter, _Reduce}, _From, State) ->
  Results = dict_filter(Filter, State),
  {reply, {ok, Results}, State};

handle_call({get_all}, _From, State) ->
  {reply, {ok, State}, State};

handle_call({get_count}, _From, State) ->
  {reply, {ok, length(State)}, State};

handle_call({truncate}, _From, _State) ->
  {reply, {ok, truncate}, []};

handle_call(_Request, _From, State) ->
  {reply, ignored, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

dict_filter(Filter, State) ->
  [ Filter(K, V) || {K, V} <- State ].
