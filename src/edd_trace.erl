%%%    Copyright (C) 2013 Enrique Martin-Martin <emartinm@fdi.ucm.es>
%%%    This file is part of Erlang Declarative Debugger.
%%%
%%%    Erlang Declarative Debugger is free software: you can redistribute it and/or modify
%%%    it under the terms of the GNU General Public License as published by
%%%    the Free Software Foundation, either version 3 of the License, or
%%%    (at your option) any later version.
%%%
%%%    Erlang Declarative Debugger is distributed in the hope that it will be useful,
%%%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%%%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%%    GNU General Public License for more details.
%%%
%%%    You should have received a copy of the GNU General Public License
%%%    along with Erlang Declarative Debugger.  If not, see <http://www.gnu.org/licenses/>.

%%%-----------------------------------------------------------------------------
%%% @author Salvador Tamarit <stamarit@dsic.upv.es>
%%% @copyright 2013 Salvador Tamarit
%%% @version 0.1
%%% @doc Erlang Declarative Debugger tracer
%%% @end
%%%-----------------------------------------------------------------------------

% TODO: We should instrument the arguments of the initial call (p.e. if it is a fun_expr)

-module(edd_trace).

-export([trace/2, trace/3]).

trace(InitialCall, PidAnswer) ->
    trace(InitialCall, PidAnswer, []).

trace(InitialCall, PidAnswer, Opts) ->
    NOpts0 =
        case proplists:is_defined(timeout, Opts) of
            true -> ok;
            false -> [{timeout, 1000} | Opts]
        end,
    NOpts1 =
        case proplists:is_defined(dir, NOpts0) of
            true -> ok;
            false -> [{dir, "."} | NOpts0]
        end,
    trace_1(InitialCall, PidAnswer, NOpts1).

trace_1(InitialCall, PidAnswer, Opts) ->
    ModName = get_mod_name(InitialCall),
    put(modules_to_instrument,[]),
    {ok, TracingNode} = 
        slave:start(
            list_to_atom(net_adm:localhost()), 
            edd_tracing, 
            "-setcookie edd_cookie"),
    Timeout = proplists:get_value(timeout, Opts),
    Dir     = proplists:get_value(dir,     Opts),
    % io:format("~p\n", [SO]),
    % io:format("~p\n~p\n", [ModName, Dir]),
    % OriginalLibCode = 
    %     [code:get_object_code(Mod) || Mod <- [gen_server, supervisor, gen_fsm, proc_lib, gen]],
    instrument_and_reload(ModName, Dir, TracingNode),
    PidMain = self(),
    PidCall = execute_call(InitialCall, self(), Dir, TracingNode),
    RunningProcs = [PidCall],
    % io:format("PIDCALL: ~p\n", [PidCall]),
    TimeoutServer = Timeout,
    InstMod = 
        get(modules_to_instrument),
    PidTrace = 
        spawn(
            fun() ->
                put(modules_to_instrument, InstMod),
                put(lambda, 0),
                receive_loop(
                    0, 
                    [],
                    [ModName], 
                    dict:new(), 
                    PidMain, 
                    TimeoutServer, 
                    Dir, 
                    TracingNode,
                    RunningProcs)
            end),
    register(edd_tracer, PidTrace),
    PidCall!start,
    receive 
        {result,Result} ->
            % io:format("TimeoutServer: ~p\n", [TimeoutServer]),
            receive 
                all_done -> ok;
                idle -> ok
            end,
            io:format("\nExecution result: ~p\n",[Result])
    after 
        Timeout ->
            io:format("\nTracing timeout\n")
    end,
    unregister(edd_tracer),
    PidTrace!stop,
    slave:stop(TracingNode),
    Trace = 
        receive 
            {trace,Trace0} ->
                lists:reverse(Trace0)
        end,
    % Loaded = % Commented to avoid warning
        receive 
            {loaded,Loaded0} ->
                Loaded0
        end,
    % [begin 
    %     {Mod, Binary, Filename} = 
    %         code:get_object_code(Mod),
    %     io:format("~p, ~s\n", [Mod, Filename]),
    %     code:load_binary(Mod, Filename, Binary)
    % end
    % || Mod <- Loaded, lists:member( Mod, [gen_server])],
    % io:format("PASA\n"),
    % [begin 
    %     {Mod, Binary, Filename} = 
    %         code:get_object_code(Mod),
    %     io:format("~p, ~s\n", [Mod, Filename]),
    %     code:load_binary(Mod, Filename, Binary)
    % end
    % || Mod <- Loaded, lists:member( Mod, [supervisor])],
    % io:format("PASA\n"),
    % [begin 
    %     {Mod, Binary, Filename} = 
    %         code:get_object_code(Mod),
    %     io:format("~p, ~s\n", [Mod, Filename]),
    %     code:load_binary(Mod, Filename, Binary)
    % end
    % || Mod <- Loaded, lists:member( Mod, [gen_fsm, proc_lib, gen])],
    % [erlang:purge_module(Mod) || Mod <- Loaded, lists:member( Mod, [gen_fsm, supervisor, proc_lib, gen])],

     % [ code:load_binary(Mod, Filename, Binary) || {Mod, Binary, Filename}  <- OriginalLibCode],
    % [undo_instrument_and_reload(Mod, Dir) || Mod <- Loaded, not(lists:member( Mod, [gen_server, gen_fsm, supervisor, proc_lib, gen]))],
    % [undo_instrument_and_reload(Mod, Dir) || Mod <- Loaded],
    % DictFun = % Commented to avoid warning
        receive 
            {fun_dict,FunDict0} ->
                FunDict0
        end,
    % unregister(edd_tracer),
    % io:format("~p\n",[dict:to_list(DictFun)]),

    % build_graph(Trace, DictFun, PidCall), 

    % io:format("~p\n",[dict:to_list(DictTraces)]),
    % io:format("Initial PID: ~p\n",[PidCall]),
    % Trace,
    % ok.
    % PidAnswer!{Trace, DictFun, PidCall}.
    PidAnswer!{Trace}.

receive_loop(Current, Trace, Loaded, FunDict, PidMain, Timeout, Dir, TracingNode, RunningProcs) ->
    % io:format("Itera\n"),
    receive 
        TraceItem = {edd_trace, _, _, _} ->
            NTraceItem =
                case TraceItem of 
                    {edd_trace, send_sent, Pid, _} ->
                        Lambda = get_lambda(),
                        Pid ! {lambda, Lambda},
                        {Pid, send, Lambda};
                    {edd_trace, made_spawn, Pid, {SpawnPid}} ->
                        {Pid, spawn, SpawnPid};
                    {edd_trace,receive_evaluated, Pid, {Lambda}} ->
                        {Pid, 'receive', Lambda};
                    _ -> 
                        TraceItem
                end,
            NRunningProcs =
                case TraceItem of
                    {edd_trace, made_spawn, _, {SpPid}} ->
                      [SpPid | RunningProcs];
                    _ ->
                        RunningProcs
                end,
            receive_loop(
                Current + 1, 
                [NTraceItem | Trace],
                Loaded, FunDict, PidMain, Timeout, Dir, TracingNode, NRunningProcs);
        {edd_load_module, Module, PidAnswer} ->
            % io:format("Load module " ++ atom_to_list(Module) ++ "\n"),
            NLoaded = 
                case lists:member(Module, Loaded) of 
                    true ->
                        PidAnswer!loaded,
                        Loaded;
                    false ->
                       instrument_and_reload(Module, Dir, TracingNode),
                       PidAnswer!loaded,
                       [Module | Loaded] 
                end, 
            receive_loop(Current, Trace, NLoaded, FunDict, PidMain, Timeout, Dir, TracingNode, RunningProcs);
        {edd_store_fun, Name, FunInfo} ->
            NFunDict = 
                case dict:is_key(Name, FunDict) of 
                    true ->
                        FunDict;
                    false ->
                        dict:append(Name, FunInfo, FunDict) 
                end, 
            receive_loop(Current, Trace, Loaded, NFunDict, PidMain, Timeout, Dir, TracingNode, RunningProcs);
        {edd_proc_done, Pid} ->
            NRunningProcs = lists:delete(Pid, RunningProcs),
            % TODO: Check also if there are no messages left in the mailbox
            case NRunningProcs of
                [] -> PidMain ! all_done;
                _ -> continue
            end,
            receive_loop(Current, Trace, Loaded, FunDict, PidMain, Timeout, Dir, TracingNode, NRunningProcs);   
        stop -> 
            PidMain!{trace, Trace},
            PidMain!{loaded, Loaded},
            PidMain!{fun_dict, FunDict};
        Other -> 
            io:format("Untracked msg ~p\n", [Other]),
            receive_loop(Current, Trace, Loaded, FunDict, PidMain, Timeout, Dir, TracingNode, RunningProcs)
    after 
        Timeout ->
            PidMain!idle,
            receive_loop(Current, Trace, Loaded, FunDict, PidMain, Timeout, Dir, TracingNode, RunningProcs)
    end.

send_module(TracingNode, Module, Dir) ->
    CompileOpts = 
        [binary, {i,Dir}, {outdir,Dir}, return],
    File = 
        get_file_path(Module, Dir),
    {ok, Module, Bin , _} = 
        compile:file(File, CompileOpts),
    {_ResL, _BadNodes} = 
        rpc:call(
            TracingNode, code, load_binary, [Module, File, Bin]),
    ok.


execute_call(Call, PidParent, _Dir, TracingNode) ->
    % spawn(
    %     TracingNode,
    send_module(TracingNode, ?MODULE, filename:absname(filename:dirname(code:which(?MODULE)) ++ "/..") ++ "/src"),
    send_module(TracingNode, smerl, filename:absname(filename:dirname(code:which(?MODULE)) ++ "/..") ++ "/src"),
    FUN = 
        fun() -> 
            % io:format("START\n")%,
            M1 = smerl:new(foo),
            {ok, M2} = 
                smerl:add_func(M1, "bar() -> try " ++ Call ++ " catch E1:E2 -> {E1,E2} end."),
            smerl:compile(M2,[nowarn_format]),
            receive 
                start -> ok 
            end,
            Res = foo:bar(), 
            PidParent!{result,Res} 
        end,
    spawn(TracingNode, FUN).
    % rpc:call(
    %     TracingNode, erlang, 'spawn', [FUN]).

get_mod_name(InitialCall) ->
    AExpr = 
        case is_list(InitialCall) of 
            true ->
                hd(parse_expr(InitialCall++"."));
            false ->
                InitialCall
        end,
    {call,_,{remote,_,{atom,_,ModName},_},_} = AExpr,
    ModName.

get_file_path(ModName, Dir) ->
    case Dir of 
        none -> 
            atom_to_list(ModName) ++ ".erl";
        _ ->
            Dir ++ "/" ++ atom_to_list(ModName) ++ ".erl"
    end.

instrument_and_reload(ModName, Dir, TracingNode) ->
    CompileOpts = 
        [{parse_transform,edd_con_pt}, binary, {i,Dir}, {outdir,Dir}, return, {inst_mod, get(modules_to_instrument)}],
    Msg = 
        "Instrumenting...",
    instrument_and_reload_gen(ModName, Dir, CompileOpts, Msg, TracingNode).

instrument_and_reload_gen(ModName, Dir, CompileOpts, Msg, TracingNode) ->
    % [gen_server, gen_fsm, supervisor, proc_lib, gen]
    case lists:member(ModName, get(modules_to_instrument)) of 
        true -> 
            instrument_and_reload_sticky(ModName, Dir, CompileOpts, Msg, TracingNode);
        false -> 
            % try 
            % CompileOpts = 
            %      [{parse_transform,edd_con_pt}, binary, {i,Dir}, {outdir,Dir}, return],
            io:format("~s~p\n", [Msg, get_file_path(ModName, Dir)]),
            % io:format("~p\n", [CompileOpts]),
            {ok,ModName,Binary,_} = 
                case compile:file(get_file_path(ModName, Dir), CompileOpts) of 
                    {ok,_,_,_} = Res ->
                        Res
                    %     ;
                    % Other ->
                    %     io:format("~p\n", [Other])
                    % _ ->
                    %     io:format("~p\n", [element(1, filename:find_src(ModName))]),
                    %     Res = compile:file(element(1, filename:find_src(ModName)) ++ ".erl", CompileOpts),
                    %     io:format("~p\n", [Res]),
                    %     Res 
                end,

                % io:format("~p\n", [get_file_path(ModName, Dir)]),
                % io:format("~p\n", [filename:find_src(ModName)]),
                % io:format("~p\n", [ file:get_cwd()]),
                %  = 
                %     compile:file(get_file_path(ModName, Dir),),
            reload_module(ModName, Binary, TracingNode)
            % catch 
            %     _:_ -> ok 
            % end.
            ,ok
    end.

instrument_and_reload_sticky(ModName, _UserDir, CompileOpts, Msg, TracingNode) ->
    LibDir = 
        code:lib_dir(stdlib, src),
    BeamDir = 
        code:lib_dir(stdlib, ebin),
    FileName = 
        get_file_path(ModName, LibDir),
    % CompileOpts = 
    %     [{parse_transform,edd_con_pt}, binary, 
    %      {i, UserDir}, {outdir, UserDir}, return],
    io:format("~s~p\n", [Msg, FileName]),
    {ok, ModName, Binary,_} = 
        case compile:file(FileName, CompileOpts) of 
            {ok,_,_,_} = Res ->
                Res;
            Other ->
                io:format("~p\n", [Other])
        end,
    % ok = 
    %     code:unstick_dir(BeamDir),
    rpc:call(
        TracingNode, code, unstick_dir, [BeamDir]),
    reload_module(ModName, Binary, TracingNode),
    rpc:call(
        TracingNode, code, stick_dir, [BeamDir]).
    % ok = 
    %     code:stick_dir(BeamDir).

% undo_instrument_and_reload(ModName, Dir) ->
%     CompileOpts = 
%         [binary, {i,Dir}, {outdir,Dir}, return],
%     Msg = 
%         "Restoring...",
%     instrument_and_reload_gen(ModName, Dir, CompileOpts, Msg).   
%     % case lists:member(ModName, [gen_server, gen_fsm, supervisor]) of 
%     %     true -> 
%     % {ok,ModName,Binary} = 
%     %     compile:file(get_file_path(ModName, Dir), [binary, {i,Dir}, {outdir,Dir}]),
%     % reload_module(ModName, Binary).

reload_module(ModName, Binary, TracingNode) ->
    try
        rpc:call(
            TracingNode, erlang, purge_module, [ModName])
    catch 
        _:_ -> ok
    end,
    rpc:call(
        TracingNode, code, load_binary, [ModName, atom_to_list(ModName) ++ ".erl", Binary]).
    % code:load_binary(ModName, atom_to_list(ModName) ++ ".erl", Binary).
    % code:load_abs(atom_to_list(ModName)).

parse_expr(Func) ->
    case erl_scan:string(Func) of
        {ok, Toks, _} ->
            case erl_parse:parse_exprs(Toks) of
                {ok, _Term} ->
                    _Term;
                _Err ->
                    {error, parse_error}
            end;
        _Err ->
            {error, parse_error}
    end.

get_lambda() ->
    Lambda = get(lambda),
    put(lambda, Lambda + 1),
    Lambda.
