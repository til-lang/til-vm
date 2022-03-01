# til-vm

Small VM embedded in [Til](https://til-lang.github.io/til/) language;

## Commands

### vm NAME (PARAMETERS) {BODY}

```tcl
vm f (x) {
    proc ten_times (x) {
        mul $x 10
    }

    # There is no "main" proc.
    # The last value in the stack is the return value of the VM.
    ten_times $x

}

print [f 10]
# 100
```
