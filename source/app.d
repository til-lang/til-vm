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
    Routine routine;

    this(string name, Routine routine)
    {
        this.name = name;
        this.routine = routine;
    }
}

alias ProcsDict = Proc[size_t];

enum Dictionary
{
    sum,
    mul,
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
                    if (command.name == entry.value.name)
                    {
                        routine ~= compileProcCall(entry.key, level);
                        break command;
                    }
                }

                // Check if it's a call to a primitive word:
                for (int i = 0; i <= Dictionary.max; i++)
                {
                    if (to!Dictionary(command.name) == i)
                    {
                        routine ~= compilePrimitiveWordCall(
                            i, level
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
    Routine compileProcCall(size_t index, int level)
    {
        return [Instruction(Opcode.call_proc, index)];
    }
    Routine compilePrimitiveWordCall(int index, int level)
    {
        return [Instruction(Opcode.call_primitive, index)];
    }

    void addProc(string name, Routine routine)
    {
        this.procs[this.procsCount++] = Proc(name, routine);
        writeln("NEW PROC: " ~ name);
        foreach(instruction; routine)
        {
            writeln(" ", instruction);
        }
    }
    void execute(Routine routine, Items arguments)
    {
        size_t[64] stack;
        size_t BP, SP = 0;

        void printStack()
        {
            string s = "[ ";
            for (auto i = 0; i < SP; i++)
            {
                s ~= to!string(stack[i]);
                if (i == BP)
                {
                    s ~= ":BP ";
                }
                else
                {
                    s ~= " ";
                }
            }
            s ~= "]";
            writeln(s);
        }

        // Fill the stack with the execution arguments:
        foreach (argument; arguments)
        {
            stack[SP++] = argument.toInt();
        }
        printStack();
        writeln("= go! =");

        size_t pop()
        {
            return stack[--SP];
        }
        void push(size_t value)
        {
            stack[SP++] = value;
        }

        // TODO: load user-defined routines (procs)
        // into memory before starting the program execution.
        // We DON'T wanna call `execute` recursively,
        // because we really want the "registers" to be
        // local variables, so that they are mapped
        // directly by the D compiler into... actual registers.

        // TODO: this is going to become a while (true)
        // with increment of IP.
        foreach (instruction; routine)
        {
            final switch (instruction.opcode)
            {
                case Opcode.push:
                    push(instruction.arg1);
                break;
                case Opcode.push_from_bp:
                    push(stack[BP + instruction.arg1]);
                break;
                case Opcode.call_primitive:
                    switch (instruction.arg1)
                    {
                        case Dictionary.sum:
                            auto a = stack[SP];
                            auto b = stack[SP - 1];
                            SP -= 1;
                            stack[SP] = a + b;
                            break;
                        case Dictionary.mul:
                            auto a = stack[SP];
                            auto b = stack[SP - 1];
                            SP -= 1;
                            stack[SP] = a * b;
                            break;
                        default:
                            throw new Exception(
                                "Unknown opcode:" ~ to!string(instruction.arg1)
                            );
                    }
                break;
                case Opcode.call_proc:
                    // auto routine = this.procs[instruction.arg1];
                    // TODO: here is where the fun begins...
                    writeln("(Not implemented yet)");
                break;
            }
            writeln(instruction);
            printStack();

        }
    }

    CommandContext run(string path, CommandContext context)
    {
        auto arguments = context.items;
        auto routine = this.compile(
            this.body.subprogram, this.parameters.items
        );
        writeln("Main program:");
        this.execute(routine, arguments);
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
