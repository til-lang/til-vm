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
    move_to_bp,
    add_to_bp,

    exec_if_success,  // Execute a routine if stack[last] is zero
    loop,

    call_proc,
    call_primitive,

    ret,
    ret_from_proc,
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
    sum, sub, mul, div,
    eq,
    push, pop,
    print,
}


class VM : Command
{
    string name;
    SimpleList parameters;
    SubProgram body;
    ProcsDict procs;
    Routine[] subroutines;
    int procsCount = 0;
    ulong code_pointer = 0;

    this(string name, SimpleList parameters, SubProgram body)
    {
        super(null);
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
command:
            foreach (command; pipeline.commandCalls)
            {
                debug {writeln("command:", command.name);}

                switch (command.name)
                {
                    case "proc":
                        compileProc(command, level);
                        continue command;
                    case "if":
                        routine ~= compileIf(command, parameters, level);
                        continue command;
                    case "loop":
                        routine ~= compileLoop(command, parameters, level);
                        continue command;
                    default:
                        break;
                }

                // Evaluate all arguments:
                foreach (index, argument; command.arguments)
                {
                    if (index == 0 && command.name == "set")
                    {
                        continue;
                    }
                    switch(argument.type)
                    {
                        case ObjectType.SubProgram:
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
                                debug {writeln("parameterNames:", parameterNames);}
                                throw new Exception("Unknown name: " ~ n);
                            }
                            break;
                        case ObjectType.Integer:
                            routine ~= Instruction(Opcode.push, argument.toInt());
                            break;
                        default:
                            throw new Exception(
                                "UNKNOWN: " ~ to!string(argument.type)
                                ~ " (" ~ to!string(argument) ~ ")"
                            );
                    }
                }

                switch (command.name)
                {
                    case "set":
                        routine ~= compileSet(
                            command,
                            parameterNames,
                            level
                        );
                        continue command;
                    case "return":
                        routine ~= Instruction(
                            Opcode.ret_from_proc,
                            0,
                            "return command", 
                        );
                        continue command;
                    case "push":
                    case "pop":
                        continue command;
                    default:
                        break;
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
    void compileProc(CommandCall command, int level)
    {
        string spacer = "";
        for (int i=0; i < level; i++)
        {
            spacer ~= " ";
        }
        string name = command.arguments[0].toString();

        if (command.arguments.length < 3)
        {
            throw new Exception(
                "proc needs 3 arguments: name, parameters list and body"
            );
        }
        auto parameters = cast(SimpleList)command.arguments[1];
        auto body = cast(SubProgram)command.arguments[2];

        Routine routine = compile(body, parameters.items);
        this.addProc(name, routine);
    }
    Routine compileIf(CommandCall command, Items parameters, int level)
    {
        Routine routine;

        if (command.arguments.length < 2)
        {
            throw new Exception("if needs 2 arguments: condition and body");
        }
        auto condition = cast(SubProgram)command.arguments[0];
        auto body = cast(SubProgram)command.arguments[1];

        // run the condition:
        routine ~= compile(condition, parameters, level + 1);

        // execute body if success/true:
        this.subroutines ~= compile(body, parameters, level + 1);
        auto index = this.subroutines.length - 1;
        routine ~= Instruction(Opcode.exec_if_success, index);

        return routine;
    }
    Routine compileLoop(CommandCall command, Items parameters, int level)
    {
        Routine routine;

        auto body = cast(SubProgram)command.arguments[0];
        this.subroutines ~= compile(body, parameters, level + 1);
        auto index = this.subroutines.length - 1;
        routine ~= Instruction(Opcode.loop, index);

        return routine;
    }
    Routine compileSet(
        CommandCall command,
        size_t[string] parameterNames,
        int level
    )
    {
        Routine routine;

        /*
        proc f (x) {
            set x [sum x 1]  # <-------------
            return $x
        }
        */
        auto n = command.arguments[0].toString();
        if (auto countPointer = n in parameterNames)
        {
            routine ~= [
                Instruction(
                    Opcode.move_to_bp,
                    *countPointer,
                    "set " ~ n
                ),
            ];
        }
        else
        {
            throw new Exception("Unknown name: " ~ n);
        }

        return routine;
    }

    void addProc(string name, Routine routine)
    {
        this.procs[this.procsCount++] = Proc(name, routine);
        debug {writeln("NEW PROC: " ~ name);}
        foreach(instruction; routine)
        {
            debug {writeln(" ", instruction);}
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
        SP--;
        foreach (argument; arguments)
        {
            stack[++SP] = argument.toInt();
        }
        debug {
            printStack("");
            writeln("= go! =");
        }

        size_t pop()
        {
            return stack[SP--];
        }
        void push(size_t value)
        {
            stack[++SP] = value;
        }

        bool executeRoutine(Routine routine)
        {
            debug {writeln("= executeRoutine =");}
            foreach (instruction; routine)
            {
                debug {
                    writeln(instruction);
                    printStack("    ");
                }

                final switch (instruction.opcode)
                {
                    case Opcode.push:
                        push(instruction.arg1);
                        break;
                    case Opcode.push_from_bp:
                        push(stack[BP + instruction.arg1]);
                        break;
                    case Opcode.move_to_bp:
                        stack[BP + instruction.arg1] = stack[SP--];
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

                        /*
                        No REAL need to `return true`, here, since
                        Opcode.ret is put automatically after a
                        user-defined procedure routine that
                        will not be running anymore
                        anyway...
                        */
                        return true;
                    case Opcode.ret_from_proc:
                        return true;
                    case Opcode.exec_if_success:
                        if (stack[SP--] == 0)
                        {
                            auto index = instruction.arg1;
                            if (executeRoutine(subroutines[index]))
                            {
                                return true;
                            }
                        }
                        break;
                    case Opcode.loop:
                        auto index = instruction.arg1;
                        int counter = 0;
                        while (true)
                        {
                            if (executeRoutine(subroutines[index]))
                            {
                                return true;
                            }
                        }
                    case Opcode.call_primitive:
                        switch (instruction.arg1)
                        {
                            case Dictionary.sum:
                                auto a = stack[SP];
                                auto b = stack[SP - 1];
                                stack[--SP] = a + b;
                                break;
                            case Dictionary.sub:
                                auto a = stack[SP];
                                auto b = stack[SP - 1];
                                stack[--SP] = a - b;
                                break;
                            case Dictionary.mul:
                                auto a = stack[SP];
                                auto b = stack[SP - 1];
                                stack[--SP] = a * b;
                                break;
                            case Dictionary.div:
                                auto a = stack[SP];
                                auto b = stack[SP - 1];
                                stack[--SP] = a / b;
                                break;
                            case Dictionary.eq:
                                auto a = stack[SP];
                                auto b = stack[SP - 1];
                                // if equals, result must be ZERO,
                                // so we invert the comparison, here:
                                stack[--SP] = (a != b);
                                break;
                            case Dictionary.print:
                                writeln(stack[--SP]);
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
                        debug {writeln("Executing procedure ", proc);}
                        executeRoutine(proc.routine);
                        break;
                }
                debug {printStack(" -> ");}
            } // end for instruction in routine
            debug {writeln("==================");}

            // true = return
            // false = end of the subroutine
            return false;
        } // end executeRoutine

        // "main" code of this function:
        executeRoutine(routine);

        debug {printStack("STACK: ");}
        return stack[SP];
    }

    override Context run(string path, Context context)
    {
        auto arguments = context.items;

        // TODO: compile at initialization
        auto routine = this.compile(
            this.body, this.parameters.items
        );

        // Force the main program to return properly:
        routine ~= Instruction(
            Opcode.ret,
            0,
            "return from main routine"
        );
        debug {writeln("Main program:");}

        auto value = this.execute(routine, arguments);

        return context.ret(new IntegerAtom(value));
    }
}

extern (C) CommandsMap getCommands(Escopo escopo)
{
    CommandsMap commands;

    commands[null] = new Command((string path, Context context)
    {
        // vm f (x) { body }
        string name = context.pop!string;
        SimpleList parameters = context.pop!SimpleList;
        SubProgram body = context.pop!SubProgram;

        auto vm = new VM(name, parameters, body);

        // Make the procedure available:
        context.escopo.commands[name] = vm;
        return context;
    });

    return commands;
}
