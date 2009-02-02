%%%-------------------------------------------------------------------
%%% File    : node_manager.erl
%%% Author  : Brad Anderson <brad@sankatygroup.com>
%%% Description : The DB Node Manager - its main purpose is to maintain
%%%               a list of all active db nodes in the cluster.
%%%               One can have different load balancing strategies
%%%               based on this list, like round-robin, least loaded,
%%%               etc.  Used by data loader and query manager.
%%%
%%% Created : 31 Jan 2009 by Brad Anderson <brad@sankatygroup.com>
%%%
%%% Thanks:  hemulen via IRC 30 Jan 2009
%%%-------------------------------------------------------------------
-module(node_manager).

-behaviour(gen_server).

%% API
-export([start_link/0, register_node/1, next_node/1, get_all_nodes/0]).

-define(SERVER, ?MODULE).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-record(state,
        {nodes=[],
         lookaside=[]}).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
  gen_server:start_link({global, ?SERVER}, ?MODULE, [], []).


register_node(DBNodePid) ->
  gen_server:call({global, ?SERVER}, {register_node, DBNodePid}).


next_node(Method) ->
  gen_server:call({global, ?SERVER}, {next_node, Method}).


get_all_nodes() ->
  gen_server:call({global, ?SERVER}, {get_all_nodes}).

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
init([]) ->
  {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------

handle_call({register_node, WorkerPid}, _From, State) ->
  link(WorkerPid),
  {reply, ok, State#state{nodes=[WorkerPid|State#state.nodes]}};

%% round robin implementation
handle_call({next_node, roundrobin}, _From, State) when
    length(State#state.nodes) > 0 ->
  [NextWorker|T] = State#state.nodes,
  {reply, NextWorker, State#state{nodes=T, lookaside=[NextWorker|State#state.lookaside]}};

handle_call({next_node, roundrobin}, _From, State) ->
  NewState = State#state{nodes=State#state.lookaside, lookaside=[]},
  [NextWorker|T] = NewState#state.nodes,
  {reply, NextWorker, State#state{nodes=T, lookaside=[NextWorker|State#state.lookaside]}};

handle_call({get_all_nodes}, _From, State) ->
   AllNodes = lists:flatten([State#state.nodes, State#state.lookaside]),
%%   AllNodes = State#state.lookaside,
  {reply, AllNodes, State};

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

handle_info({'EXIT', From, _Reason}, State) ->
  #state{nodes=Nodes, lookaside=Lookaside} = State,
  {noreply, State#state{nodes=filter_worker(From, Nodes), lookaside=filter_worker(From, Lookaside)}};

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
filter_worker(WorkerPid, Workers) ->
  lists:filter(fun(WP) -> (WP =:= WorkerPid) == false end, Workers).
