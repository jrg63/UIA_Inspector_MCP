# UIA Inspector MCP — Test Script

Copy each section below into Copilot Chat to exercise the UIA Inspector MCP server.
These tests require the AHK engine to be running (VS Code status bar should show ▶ UIA MCP).

---

## 1. list_windows — enumerate all desktop windows

```
list all the windows open on the desktop
```

**Validates:** `list_windows` tool. Should return window titles, HWNDs, PIDs, exe paths, and visibilities.

---

## 2. list_windows with filter

```
list windows with "Edge" in the title
```

**Validates:** `list_windows` with `filter` parameter.

---

## 3. get_window_info — inspect a specific window

First get a window HWND from step 1, then:

```
get detailed info for the window with HWND 0x... (use an actual HWND from the previous list)
```

**Validates:** `get_window_info` tool. Should show title, class, exe, PID, rect, elevation.

---

## 4. get_element_tree — explore window structure

```
show me the UIA element tree for the VS Code window, depth 3
```

**Validates:** `get_element_tree` tool. Should return a compact tree of element types, names, AutomationIds.

> ⚠️ **Note:** If this tool reports "disabled by the user," open Copilot Chat's MCP tool manager (🔧 icon in chat input) and uncheck `get_element_tree` under the UIA Inspector server.

---

## 5. get_focused_element — inspect keyboard focus

```
what element currently has keyboard focus?
```

**Validates:** `get_focused_element` tool. Should report the focused control.

---

## 6. inspect_element_at_cursor — element under mouse

```
identify the element under my mouse cursor
```

**Validates:** `inspect_element_at_cursor` tool. Should return element properties, patterns, ancestor chain, and inferred action.

---

## 7. find_element — locate a specific control

```
find the first Button named "OK" in the desktop
```

**Validates:** `find_element` tool with condition `{Type:"Button", Name:"OK"}`.

---

## 8. find_element with Contains match

```
find all Edit fields in the VS Code window
```

**Validates:** `find_all_elements` tool with `{Type:"Edit"}`. Then pick one, and:

```
find a button in the VS Code window whose name contains "File"
```

**Validates:** `find_element` with `matchMode:"Contains"`.

---

## 9. check_match_count — count before finding

```
how many Button elements are in the VS Code window?
```

**Validates:** `check_match_count` tool. Should return a count without full element data.

---

## 10. get_child_elements — get direct children

First get a focused element or find one, then:

```
get the direct children of the focused element
```

**Validates:** `get_child_elements` tool. Returns summaries for each direct child.

---

## 11. get_element_properties — full property dump

```
get all UIA properties for the focused element
```

**Validates:** `get_element_properties` tool. Should return a rich set of UIA property values.

---

## 12. get_element_patterns — available interaction patterns

```
what UIA patterns are available on the focused element?
```

**Validates:** `get_element_patterns` tool. Returns Invoke, Value, Selection, etc.

---

## 13. get_ancestor_chain — walk up the tree

```
show me the ancestor chain from the focused element up to the root
```

**Validates:** `get_ancestor_chain` tool. Root-first array of ancestor summaries.

---

## 14. get_bounding_rect — screen coordinates

```
what is the bounding rectangle of the focused element?
```

**Validates:** `get_bounding_rect` tool. Returns `{left, top, right, bottom}`.

---

## 15. wait_for_element — poll until present

```
wait up to 5 seconds for a Button named "Cancel" to appear in the desktop
```

**Validates:** `wait_for_element` tool. Returns `{found: true/false, element: ...}`.

---

## 16. get_element_at_point — element at screen coordinates

First get a bounding rect from a known element (e.g., the focused element), then:

```
what element is at screen coordinates (x, y)? (use the center of the bounding rect from the previous step)
```

**Validates:** `get_element_at_point` tool.

---

## 17. Combined workflow — find then chain

```
1. Find the first edit control in VS Code
2. Get its ancestor chain
3. Get its bounding rect
4. Check what patterns it supports
```

**Validates:** Multi-step tool chaining in a single prompt.

---

## 18. uia_get_element_code — generate runnable script for a specific element

First find an element (e.g., a button in VS Code or Notepad), then:

```
generate a complete AHK v2 automation script for the button named "OK" in the current window
```

Or more precisely:

```
use uia_get_element_code to generate code that targets {Type: "Button", Name: "OK"} in the current window
```

**Validates:** `uia_get_element_code` tool. Should return a complete, runnable `.ahk` script with `#Requires`, `#Include <UIA>`, `Main()`/`ExitApp`, `local winEl := ...`, `local el := ...`, and `el.Action()`.

---

## 19. uia_get_code_recipe — get code templates

```
show me the available code recipes for UIA automation
```

Then:

```
give me the find_and_click recipe
```

**Validates:** `uia_get_code_recipe` tool. Should return proven AHK v2 code templates.

---

## Summary

| #  | Tool                     | Tested |
|----|--------------------------|--------|
| 1  | `list_windows`           | ☐      |
| 2  | `list_windows` (filter)  | ☐      |
| 3  | `get_window_info`        | ☐      |
| 4  | `get_element_tree`       | ☐      |
| 5  | `get_focused_element`    | ☐      |
| 6  | `inspect_element_at_cursor` | ☐   |
| 7  | `find_element`           | ☐      |
| 8  | `find_all_elements`      | ☐      |
| 9  | `check_match_count`      | ☐      |
| 10 | `get_child_elements`     | ☐      |
| 11 | `get_element_properties` | ☐      |
| 12 | `get_element_patterns`   | ☐      |
| 13 | `get_ancestor_chain`     | ☐      |
| 14 | `get_bounding_rect`      | ☐      |
| 15 | `wait_for_element`       | ☐      |
| 16 | `get_element_at_point`   | ☐      |
| 17 | Multi-step chaining      | ☐      |
| 18 | `uia_get_element_code`  | ☐      |
| 19 | `uia_get_code_recipe`   | ☐      |
