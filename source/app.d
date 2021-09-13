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
    add_to_bp,
    ret,

    call_proc,
    call_primitive,
}


struct Instruction
{
    Opcode opcode;
    size_t arg1;
    string comment;

    this(Opcode opcode)
    {
        this(opcode, 0);
    }
    this(Opcode opcode, string comment)
    {
        this(opcode, 0, comment);
    }
    this(Opcode opcode, size_t arg1)
    {
        this(opcode, arg1, "");
    }
    this(Opcode opcode, size_t arg1, string comment)
    {
        this.opcode = opcode;
        this.arg1 = arg1;
        this.comment = comment;
    }

    string toString()
    {
        auto s = to!string(this.opcode) ~ " " ~ to!string(this.arg1);
        if (this.comment.length > 0)
        {
            s ~= "  # " ~ this.comment;
        }
        return s;
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
    string toString()
    {
        return this.name;
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
    ulong code_pointer = 0;

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
        return compile(subprogram, parameters, 0, level);
    }
    Routine compile(
        SubProgram subprogram,
        Items parameters,
        size_t nextBPOffset,
        int level
    )
    {
        Routine routine;

        size_t[string] parameterNames;
        foreach (index, parameter; parameters)
        {
            // a b c   .length = 3
            // 0 1 2   index
            // 2 1 0
            auto name = parameter.toString();
            //parameterNames[name] = parameters.length - index - 1;
            parameterNames[name] = index;
        }

        string spacer = "";
        for (int i=0; i < level; i++)
        {
            spacer ~= " ";
        }

        foreach (pipeline; subprogram.pipelines)
        {
            foreach (command; pipeline.commands)
            {
                if (command.name == "proc")
                {
                    compileProc(command, level);
                    continue;
                }

                // Evaluate all arguments:
                foreach (index, argument; command.arguments)
                {
                    switch(argument.type)
                    {
                        case ObjectType.SubList:
                            throw new Exception(
                                "VM should not compile a SubProgram"
                            );
                        case ObjectType.ExecList:
                            // The SubProgram itself is going
                            // to save and restore its own BP:
                            routine ~= compile(
                                (cast(ExecList)argument).subprogram,
                                parameters,
                                nextBPOffset + 1,
                                level + 1
                            );
                            break;
                        case ObjectType.Name:
                            auto n = argument.toString();
                            if (auto countPointer = n in parameterNames)
                            {
                                routine ~= Instruction(
                                    Opcode.push_from_bp,
                                    *countPointer,
                                    "$" ~ n
                                );
                                nextBPOffset += 1;
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
                bool isProc = false;
                foreach (entry; this.procs.byPair)
                {
                    if (command.name == entry.value.name)
                    {
                        isProc = true;

                        routine ~= Instruction(Opcode.add_to_bp, nextBPOffset);
                        routine ~= Instruction(
                            Opcode.call_proc, entry.key, command.name
                        );
                        routine ~= Instruction(
                            Opcode.ret,
                            nextBPOffset,
                            "return from " ~ command.name
                            ~ " with offset " ~ to!string(nextBPOffset)
                        );

                        break;
                    }
                }
                if (!isProc)
                {
                    // Check if it's a call to a primitive word:
                    for (int i = 0; i <= Dictionary.max; i++)
                    {
                        if (to!Dictionary(command.name) == i)
                        {
                            routine ~= Instruction(
                                Opcode.call_primitive, i, command.name
                            );
                            break;
                        }
                    }
                }
            } // end foreach command
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

    void addProc(string name, Routine routine)
    {
        this.procs[this.procsCount++] = Proc(name, routine);
        writeln("NEW PROC: " ~ name);
        foreach(instruction; routine)
        {
            writeln(" ", instruction);
        }
    }
    size_t execute(Routine routine, Items arguments)
    {
        size_t[64] stack;
        size_t BP, SP = 0;

        void printStack(string prefix)
        {
            string s = prefix ~ "[ ";
            for (auto i = 0; i <= SP; i++)
            {
                if (i == BP)
                {
                    s ~= "(" ~ to!string(stack[i]) ~ ") ";
                }
                else
                {
                    s ~= to!string(stack[i]) ~ " ";
                }
            }
            s ~= "] " ~ to!string(SP);
            writeln(s);
        }

        // Fill the stack with the execution arguments:
        SP -= 1;
        foreach (argument; arguments)
        {
            stack[++SP] = argument.toInt();
        }
        printStack("");
        writeln("= go! =");

        size_t pop()
        {
            return stack[SP--];
        }
        void push(size_t value)
        {
            stack[++SP] = value;
        }

        void executeRoutine(Routine routine)
        {
            writeln("= executeRoutine =");
            foreach (instruction; routine)
            {
                writeln(instruction);
                printStack("    ");

                final switch (instruction.opcode)
                {
                    case Opcode.push:
                        push(instruction.arg1);
                    break;
                    case Opcode.push_from_bp:
                        push(stack[BP + instruction.arg1]);
                    break;
                    case Opcode.add_to_bp:
                        BP += instruction.arg1;
                    break;
                    case Opcode.ret:
                        // Put the last pushed value
                        // into BP (return value address):
                        stack[BP] = stack[SP];
                        // Ignore everything else:
                        SP = BP;
                        // Move BP to the old position:
                        BP -= instruction.arg1;
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
                                    "Unknown opcode:"
                                    ~ to!string(instruction.arg1)
                                );
                        }
                    break;
                    case Opcode.call_proc:
                        auto proc = this.procs[instruction.arg1];
                        writeln("Executing procedure ", proc);
                        executeRoutine(proc.routine);
                    break;
                }
                printStack(" -> ");
            } // end for instruction in routine
            writeln("==================");
        } // end executeRoutine

        // "main" code of this function:
        executeRoutine(routine);

        printStack("STACK: ");
        return stack[0];
    }

    CommandContext run(string path, CommandContext context)
    {
        auto arguments = context.items;
        auto routine = this.compile(
            this.body.subprogram, this.parameters.items
        );
        // Force the main program to return properly:
        routine ~= Instruction(
            Opcode.ret,
            0,
            "return from main routine"
        );
        writeln("Main program:");
        auto value = this.execute(routine, arguments);
        return context.ret(new IntegerAtom(value));
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
