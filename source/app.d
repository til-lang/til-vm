import std.array : byPair;
import std.process;
import std.stdio : readln;
import std.string : strip;

import til.nodes;

import std.stdio : writeln;


enum Opcode
{
    push,
    push_from_bp,
    pop_to_sp,

    call_proc,
    call_primitive,
}


struct Instruction
{
    Opcode opcode;
    size_t arg1;

    this(Opcode opcode, size_t arg1)
    {
        this.opcode = opcode;
        this.arg1 = arg1;
    }

    string toString()
    {
        return to!string(this.opcode) ~ " " ~ to!string(this.arg1);
    }
}

alias Routine = Instruction[];

struct Proc
{
    string name;
    int index;
    Routine routine;

    this(string name, int index, Routine routine)
    {
        this.name = name;
        this.index = index;
        this.routine = routine;
    }
}

alias ProcsDict = Proc[string];


class Stack
{
    int[64] stack;
    size_t BP;
    size_t SP;

    this()
    {
        this.SP = 0;
    }

    int pop()
    {
        return stack[SP--];
    }
    void push(int v)
    {
        stack[++SP] = v;
    }
}


alias PrimitiveWord = void function(Stack);

PrimitiveWord[string] primitiveWords;
string[] dictionary;

static this()
{
    primitiveWords["sum"] = function(Stack stack)
    {
        stack.push(
            stack.pop() + stack.pop()
        );
    };
    primitiveWords["mul"] = function(Stack stack)
    {
        stack.push(
            stack.pop() * stack.pop()
        );
    };

    // Index each opcode by number:
    foreach(entry; primitiveWords.byPair)
    {
        dictionary ~= entry.key;
    }
}


class VM : ListItem
{
    string name;
    SimpleList parameters;
    SubList body;
    ProcsDict procs;
    int procsCount = 0;

    this(string name, SimpleList parameters, SubList body)
    {
        this.name = name;
        this.parameters = parameters;
        this.body = body;
    }

    Routine compile(SubProgram subprogram, Items parameters)
    {
        return compile(subprogram, parameters, 0);
    }
    Routine compile(SubProgram subprogram, Items parameters, int level)
    {
        Routine routine;

        size_t[string] parameterNames;
        foreach(index, parameter; parameters)
        {
            // a b c   .length = 3
            // 0 1 2   index
            // 2 1 0
            auto name = parameter.toString();
            parameterNames[name] = parameters.length - index - 1;
        }

        string spacer = "";
        for (int i=0; i < level; i++)
        {
            spacer ~= " ";
        }

        foreach(pipeline; subprogram.pipelines)
        {
command:
            foreach(command; pipeline.commands)
            {
                if (command.name == "proc")
                {
                    compileProc(command, level);
                    continue;
                }

                // Evaluate all arguments:
                foreach(argument; command.arguments.retro)
                {
                    switch(argument.type)
                    {
                        case ObjectType.SubList:
                            throw new Exception(
                                "VM should not compile a SubProgram"
                            );
                        case ObjectType.ExecList:
                            routine ~= compile(
                                (cast(ExecList)argument).subprogram,
                                parameters,
                                level + 1
                            );
                            break;
                        case ObjectType.Name:
                            auto n = argument.toString();
                            if (auto countPointer = n in parameterNames)
                            {
                                // TODO: define the call stack properly!
                                routine ~= Instruction(
                                    Opcode.push_from_bp, *countPointer
                                );
                            }
                            else
                            {
                                writeln("parameterNames:", parameterNames);
                                throw new Exception("Unknown name: " ~ n);
                            }
                            break;
                        default:
                            writeln(
                                spacer,
                                "UNKNOWN> ", argument.type, " (", argument, ")"
                            );
                    }
                }
                // Check if it's a call to a user-defined procedure:
                foreach(entry; this.procs.byPair)
                {
                    if (command.name == entry.key)
                    {
                        routine ~= compileProcCall(entry.value, level);
                        break command;
                    }
                }

                // Check if it's a call to a primitive word:
                foreach(index, opcode; dictionary)
                {
                    if (command.name == opcode)
                    {
                        routine ~= compilePrimitiveWordCall(
                            cast(int)index, level
                        );
                        break command;
                    }
                }
            }
        }
        return routine;
    }
    void compileProc(Command command, int level)
    {
        string spacer = "";
        for (int i=0; i < level; i++)
        {
            spacer ~= " ";
        }
        string name = command.arguments[0].toString();

        // TODO: check for array size!
        auto parameters = cast(SimpleList)command.arguments[1];
        auto body = cast(SubList)command.arguments[2];

        Routine routine = compile(body.subprogram, parameters.items);
        this.addProc(name, routine);
    }
    Routine compileProcCall(Proc proc, int level)
    {
        return [Instruction(Opcode.call_proc, proc.index)];
    }
    Routine compilePrimitiveWordCall(int index, int level)
    {
        return [Instruction(Opcode.call_primitive, index)];
    }

    void addProc(string name, Routine routine)
    {
        this.procs[name] = Proc(name, this.procsCount++, routine);
        writeln("NEW PROC: " ~ name);
        foreach(instruction; routine)
        {
            writeln(" ", instruction);
        }
    }
    void execute(Routine routine)
    {
        foreach(instruction; routine)
        {
            this.executeInstruction(instruction);
        }
    }
    void executeInstruction(Instruction instruction)
    {
        final switch(instruction.opcode)
        {
            case Opcode.push:
            break;
            case Opcode.push_from_bp:
            break;
            case Opcode.pop_to_sp:
            break;
            case Opcode.call_proc:
            break;
            case Opcode.call_primitive:
            break;
        }
        writeln(instruction);
    }

    CommandContext run(string path, CommandContext context)
    {
        auto arguments = context.items;
        auto routine = this.compile(this.body.subprogram, this.parameters.items);
        writeln("Main program:");
        this.execute(routine);
        // TESTE:
        return context.ret(new IntegerAtom(7));
    }
}


extern (C) CommandHandler[string] getCommands(Process escopo)
{
    CommandHandler[string] commands;

    commands[null] = (string path, CommandContext context)
    {
        // vm f (x) { body }
        string name = context.pop!string;
        SimpleList parameters = context.pop!SimpleList;
        SubList body = context.pop!SubList;

        auto vm = new VM(name, parameters, body);

        CommandContext closure(string path, CommandContext context)
        {
            return vm.run(path, context);
        }

        // Make the procedure available:
        context.escopo.commands[name] = &closure;

        context.exitCode = ExitCode.CommandSuccess;
        return context;
    };

    return commands;
}
