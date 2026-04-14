# DBF Table sample — inspector dropdowns demo

Minimal one-form project that exercises the two new dropdowns in the
Windows inspector.

## Open it

1. Launch HarbourBuilder (`bin\hbbuilder_win.exe`).
2. Open `Project1.hbp`.
3. `Form1` shows in the designer: a label, an edit, a button, and a
   non-visual `oDbfTable1` under the component well.

## What to test

### 1 · `cRDD` (string-valued dropdown)

Click `oDbfTable1` (the non-visual component). In the inspector, find
`cRDD` under the Data category. Click the value → a combobox opens
with three entries:

- `DBFCDX` (default)
- `DBFNTX`
- `DBFFPT`

Pick one. The designer persists the chosen string verbatim (not an
index) and the generated form code reflects it:
`::oDbfTable1:cRDD := "DBFFPT"`.

### 2 · Yes/No (every logical property)

Click any control and open any `l...` property. Examples:

| Control      | Property                                   |
|--------------|--------------------------------------------|
| The form     | `lSizable`, `lVisible`, `lEnabled`         |
| `oLabel1`    | `lVisible`, `lEnabled`, `lTabStop`         |
| `oEdit1`     | `lReadOnly`, `lPassword`, `lVisible`       |
| `oButton1`   | `lDefault`, `lCancel`, `lEnabled`          |

Each one now opens a dropdown with just `No` and `Yes` instead of a
free-text edit that required typing `.T.` or `.F.`. The picker writes
the correct `.T.` / `.F.` into the generated code.

## App name

`::AppTitle := "DbfTableDemo"` is set in `CreateForm`, so the build
produces `c:\hbbuilder_build\DbfTableDemo.exe` instead of
`UserApp.exe`.
