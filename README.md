# til-vm

Small VM embedded in [Til](https://til-lang.github.io/til/) language;

## Commands

### vm NAME (PARAMETERS) {BODY}

```tcl
vm f (x) {
    proc f (x) {
        return [mul $x 10]
    }

    return [f $x]
}

print [f 10]  # == 100
```
