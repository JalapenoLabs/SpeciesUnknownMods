#!/usr/bin/env python3
# Copyright © 2026 Jalapeno Labs
"""Print a Blueprint's Kismet bytecode as readable pseudo-code.

Reads the JSON that `kismet-analyzer to-json` writes for a cooked asset and prints every function export as one
statement per line. It is a reading aid, not a decompiler: jumps print their byte offsets as targets, and
expressions without a dedicated format fall back to their UAssetAPI type and fields.

See docs/reverse-engineering.md for how to produce the JSON, including the minimal mappings file that lets
kismet-analyzer parse function exports of an asset with unversioned properties.

Usage: kismet_pseudocode.py <asset.json> [function name filter]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


class PseudocodePrinter:
    """Formats UAssetAPI Kismet expression trees, resolving package indices against one asset."""

    def __init__(self, asset: dict) -> None:
        self._imports: list[dict] = asset["Imports"]
        self._exports: list[dict] = asset["Exports"]

    def resolve(self, package_index: int) -> str:
        """Name the import (negative) or export (positive) a package index points at."""
        if package_index < 0:
            return self._imports[-package_index - 1]["ObjectName"]
        if package_index > 0:
            return self._exports[package_index - 1]["ObjectName"]
        return "null"

    def expression(self, node: dict | None) -> str:
        """Format one expression and everything under it."""
        if node is None:
            return "<none>"

        # `UAssetAPI.Kismet.Bytecode.Expressions.EX_LetBool, UAssetAPI` -> `EX_LetBool`
        expression_type = node["$type"].split(",")[0].rsplit(".", 1)[-1]
        formatter = _FORMATTER_BY_TYPE.get(expression_type)
        if formatter is not None:
            return formatter(self, node)

        # Unknown expression: show its type and fields, formatting nested expressions where we find them.
        fields = []
        for key, value in node.items():
            if key == "$type":
                continue
            fields.append(f"{key}={self._value(value)}")
        return f"{expression_type}({', '.join(fields)})"

    def _value(self, value: object) -> str:
        if isinstance(value, dict) and "$type" in value and ".Expressions." in value["$type"]:
            return self.expression(value)
        if isinstance(value, list):
            return "[" + ", ".join(self._value(item) for item in value) + "]"
        return json.dumps(value)

    def call(self, name: str, parameters: list[dict]) -> str:
        """Format a function call with its arguments."""
        arguments = ", ".join(self.expression(parameter) for parameter in parameters)
        return f"{name}({arguments})"


def _variable_name(node: dict) -> str:
    path = node["Variable"]["New"]["Path"]
    return ".".join(path) if path else "<unnamed>"


def _format_let(printer: PseudocodePrinter, node: dict) -> str:
    target = printer.expression(node.get("VariableExpression") or node.get("Variable"))
    value = printer.expression(node.get("AssignmentExpression") or node.get("Expression"))
    return f"{target} = {value}"


def _format_context(printer: PseudocodePrinter, node: dict) -> str:
    owner = printer.expression(node["ObjectExpression"])
    member = printer.expression(node["ContextExpression"])
    return f"{owner}.{member}"


def _format_jump_if_not(printer: PseudocodePrinter, node: dict) -> str:
    condition = printer.expression(node["BooleanExpression"])
    return f"if not {condition}: goto {node['CodeOffset']}"


_FORMATTER_BY_TYPE = {
    "EX_LocalVariable": lambda printer, node: _variable_name(node),
    "EX_LocalOutVariable": lambda printer, node: f"out {_variable_name(node)}",
    "EX_InstanceVariable": lambda printer, node: f"self.{_variable_name(node)}",
    "EX_DefaultVariable": lambda printer, node: f"default.{_variable_name(node)}",
    "EX_Self": lambda printer, node: "self",
    "EX_Nothing": lambda printer, node: "nothing",
    "EX_NoObject": lambda printer, node: "None",
    "EX_True": lambda printer, node: "true",
    "EX_False": lambda printer, node: "false",
    "EX_IntConst": lambda printer, node: str(node["Value"]),
    "EX_Int64Const": lambda printer, node: f"{node['Value']}L",
    "EX_ByteConst": lambda printer, node: f"byte {node['Value']}",
    "EX_IntConstByte": lambda printer, node: f"byte {node['Value']}",
    "EX_FloatConst": lambda printer, node: str(node["Value"]),
    "EX_DoubleConst": lambda printer, node: str(node["Value"]),
    "EX_NameConst": lambda printer, node: f"name'{node['Value']}'",
    "EX_StringConst": lambda printer, node: json.dumps(node["Value"]),
    "EX_UnicodeStringConst": lambda printer, node: json.dumps(node["Value"]),
    "EX_ObjectConst": lambda printer, node: f"object'{printer.resolve(node['Value'])}'",
    "EX_StructConst": lambda printer, node: printer.call(
        f"struct {printer.resolve(node['Struct'])}",
        node["Value"],
    ),
    "EX_Let": _format_let,
    "EX_LetBool": _format_let,
    "EX_LetObj": _format_let,
    "EX_LetWeakObjPtr": _format_let,
    "EX_LetDelegate": _format_let,
    "EX_LetMulticastDelegate": _format_let,
    "EX_LetValueOnPersistentFrame": lambda printer, node: (
        f"persistent.{node['DestinationProperty']['New']['Path'][0]} = "
        f"{printer.expression(node['AssignmentExpression'])}"
    ),
    "EX_CallMath": lambda printer, node: printer.call(printer.resolve(node["StackNode"]), node["Parameters"]),
    "EX_FinalFunction": lambda printer, node: printer.call(printer.resolve(node["StackNode"]), node["Parameters"]),
    "EX_LocalFinalFunction": lambda printer, node: printer.call(
        printer.resolve(node["StackNode"]),
        node["Parameters"],
    ),
    "EX_VirtualFunction": lambda printer, node: printer.call(node["VirtualFunctionName"], node["Parameters"]),
    "EX_LocalVirtualFunction": lambda printer, node: printer.call(node["VirtualFunctionName"], node["Parameters"]),
    "EX_Context": _format_context,
    "EX_Context_FailSilent": _format_context,
    "EX_InterfaceContext": lambda printer, node: printer.expression(node["InterfaceValue"]),
    "EX_DynamicCast": lambda printer, node: (
        f"cast<{printer.resolve(node['ClassPtr'])}>({printer.expression(node['Target'])})"
    ),
    "EX_MetaCast": lambda printer, node: (
        f"cast<{printer.resolve(node['ClassPtr'])}>({printer.expression(node['Target'])})"
    ),
    "EX_ObjToInterfaceCast": lambda printer, node: (
        f"cast<{printer.resolve(node['ClassPtr'])}>({printer.expression(node['Target'])})"
    ),
    "EX_PrimitiveCast": lambda printer, node: f"convert({printer.expression(node['Target'])})",
    "EX_Jump": lambda printer, node: f"goto {node['CodeOffset']}",
    "EX_JumpIfNot": _format_jump_if_not,
    "EX_ComputedJump": lambda printer, node: f"goto computed {printer.expression(node['CodeOffsetExpression'])}",
    "EX_PushExecutionFlow": lambda printer, node: f"push flow {node['PushingAddress']}",
    "EX_PopExecutionFlow": lambda printer, node: "pop flow",
    "EX_PopExecutionFlowIfNot": lambda printer, node: (
        f"if not {printer.expression(node['BooleanExpression'])}: pop flow"
    ),
    "EX_Return": lambda printer, node: f"return {printer.expression(node['ReturnExpression'])}",
    "EX_EndOfScript": lambda printer, node: "end",
    "EX_ArrayGetByRef": lambda printer, node: (
        f"{printer.expression(node['ArrayVariable'])}[{printer.expression(node['ArrayIndex'])}]"
    ),
    "EX_StructMemberContext": lambda printer, node: (
        f"{printer.expression(node['StructExpression'])}.{'.'.join(node['StructMemberExpression']['New']['Path'])}"
    ),
    "EX_SetArray": lambda printer, node: printer.call(
        f"{printer.expression(node['AssigningProperty'])} = array",
        node["Elements"],
    ),
}


def main() -> None:
    """Print every function export in the asset, optionally only those whose name contains a filter."""
    if len(sys.argv) not in (2, 3):
        sys.exit(f"Usage: {Path(sys.argv[0]).name} <asset.json> [function name filter]")

    asset = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    name_filter = sys.argv[2].lower() if len(sys.argv) == 3 else ""
    printer = PseudocodePrinter(asset)

    printed_count = 0
    for export in asset["Exports"]:
        bytecode = export.get("ScriptBytecode")
        if bytecode is None or name_filter not in export["ObjectName"].lower():
            continue

        printed_count += 1
        print(f"\n== {export['ObjectName']}")
        for statement in bytecode:
            print(f"  {printer.expression(statement)}")

    if printed_count == 0:
        sys.exit(
            "No function bytecode found. Exports are probably still raw: pass kismet-analyzer a mappings file "
            "(docs/reverse-engineering.md)."
        )


if __name__ == "__main__":
    main()
