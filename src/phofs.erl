%% ---
%%  Excerpted from "Programming Erlang",
%%  published by The Pragmatic Bookshelf.
%%  Copyrights apply to this code. It may not be used to create training material,
%%  courses, books, articles, and the like. Contact us if you are in doubt.
%%  We make no guarantees that this code is fit for any purpose.
%%  Visit http://www.pragmaticprogrammer.com/titles/jaerlang for more book information.
%% ---

%% Parallel Higher Order FunctionS module

-module(phofs).

-export([mapreduce/4, pmap/2]).

-include_lib("eunit/include/eunit.hrl").


%% FMap(Pid, X) -> sends {Key,Val} messages to Pid
%% FReduce(Key, [Val], AccIn) -> AccOut
%% Acc0 is the initial value of the accumulator
%% L is the list of values
mapreduce(FMap, FReduce, Acc0, L) ->
  S = self(),
  Pid = spawn(fun() -> reduce(S, FMap, FReduce, Acc0, L) end),
  receive
    {Pid, Result} ->
      Result
  end.


%% the reduce function process (running Pid from mapreduce/4)
reduce(Parent, Map, Reduce, Acc0, L) ->
  process_flag(trap_exit, true),
  ReducePid = self(),

  %% Create the Map processes
  %%   One for each element X in L
  lists:foreach(fun(X) ->
                    spawn_link(fun() -> do_map(ReducePid, Map, X) end)
                end, L),
  N = length(L),

  %% make an ets table to store the [{K,[V]}] results
  Table = ets:new('reduce', [set, private]),

  %% Wait for N Map processes to terminate
  %% TODO: handle fewer than N processes terminating?  in collect_replies ?
  Results = case collect_replies(N, Table, 0) of
              ok ->
                ets:foldl(Reduce, Acc0, Table);
              Error ->
                Error
            end,
  Parent ! {self(), Results}.


%% collect_replies(N, Table, Count)
%%     collect and merge {Key, Value} messages from N processes.
%%     When N processes have terminated return ok
collect_replies(0, _Table, _MapCount) ->
  %%?debugFmt("~w map msgs sent~n", [MapCount]),
  ok;
collect_replies(N, Table, MapCount) ->
  receive
    {Key, Val} ->
      Lookup = ets:lookup(Table, Key),
      NewVal = case Lookup of
                 [] ->
                   [Val];
                 _ ->
                   [{Key, OldVal}] = Lookup,
                   lists:flatten([Val, OldVal])
               end,
      %% don't care if overwrite
      ets:insert(Table, {Key, NewVal}),
      collect_replies(N, Table, MapCount+1);
    {'EXIT', _,  _Why} ->
      collect_replies(N-1, Table, MapCount)
  end.


%% Call F(Pid, X)
%%   F must send {Key, Value} messsages to Pid
%%     and then terminate
do_map(ReducePid, FMap, X) ->
  FMap(ReducePid, X).


%% %% Parallelizing map.  Stolen verbatim from book.
%% pmap(F, L) ->
%%     S = self(),
%%     %% make_ref() returns a unique reference
%%     %%   we'll match on this later
%%     Ref = erlang:make_ref(),
%%     Pids = lists:map(fun(I) ->
%% 		       spawn(fun() -> do_f(S, Ref, F, I) end)
%% 	       end, L),
%%     %% gather the results
%%     gather(Pids, Ref).

%% do_f(Parent, Ref, F, I) ->
%%     Parent ! {self(), Ref, (catch F(I))}.

%% gather([Pid|T], Ref) ->
%%     receive
%% 	{Pid, Ref, Ret} -> [Ret|gather(T, Ref)]
%%     end;
%% gather([], _) ->
%%     [].


%% %% pmap that doesn't care about order returned (also from book)
%% pmap1(F, L) ->
%%     S = self(),
%%     Ref = erlang:make_ref(),
%%     foreach(fun(I) ->
%% 		    spawn(fun() -> do_f1(S, Ref, F, I) end)
%% 	    end, L),
%%     %% gather the results
%%     gather1(length(L), Ref, []).

%% do_f1(Parent, Ref, F, I) ->
%%     Parent ! {Ref, (catch F(I))}.

%% gather1(0, _, L) -> L;
%% gather1(N, Ref, L) ->
%%     receive
%% 	{Ref, Ret} -> gather1(N-1, Ref, [Ret|L])
%%     end.


%% pmap from Luke Gorrie and http://lukego.livejournal.com/6753.html
pmap(F,List) ->
  [wait_result(Worker) || Worker <- [spawn_worker(self(),F,E) || E <- List]].

spawn_worker(Parent, F, E) ->
  erlang:spawn_monitor(fun() -> Parent ! {self(), F(E)} end).

wait_result({Pid,Ref}) ->
  receive
    {'DOWN', Ref, _, _, normal} -> receive {Pid,Result} -> Result end;
    {'DOWN', Ref, _, _, Reason} -> exit(Reason)
  end.
