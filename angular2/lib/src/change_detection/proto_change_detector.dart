library angular2.src.change_detection.proto_change_detector;

import "package:angular2/src/facade/lang.dart"
    show BaseException, Type, isBlank, isPresent, isString;
import "package:angular2/src/facade/collection.dart"
    show List, ListWrapper, MapWrapper, StringMapWrapper;
import "parser/ast.dart"
    show
        AccessMember,
        Assignment,
        AST,
        ASTWithSource,
        AstVisitor,
        Binary,
        Chain,
        Conditional,
        Pipe,
        FunctionCall,
        ImplicitReceiver,
        Interpolation,
        KeyedAccess,
        LiteralArray,
        LiteralMap,
        LiteralPrimitive,
        MethodCall,
        PrefixNot;
import "interfaces.dart"
    show
        ChangeDispatcher,
        ChangeDetector,
        ProtoChangeDetector,
        ChangeDetectorDefinition;
import "change_detection_util.dart" show ChangeDetectionUtil;
import "dynamic_change_detector.dart" show DynamicChangeDetector;
import "change_detection_jit_generator.dart" show ChangeDetectorJITGenerator;
import "pipes/pipe_registry.dart" show PipeRegistry;
import "binding_record.dart" show BindingRecord;
import "directive_record.dart" show DirectiveRecord, DirectiveIndex;
import "coalesce.dart" show coalesce;
import "proto_record.dart"
    show
        ProtoRecord,
        RECORD_TYPE_SELF,
        RECORD_TYPE_PROPERTY,
        RECORD_TYPE_LOCAL,
        RECORD_TYPE_INVOKE_METHOD,
        RECORD_TYPE_CONST,
        RECORD_TYPE_INVOKE_CLOSURE,
        RECORD_TYPE_PRIMITIVE_OP,
        RECORD_TYPE_KEYED_ACCESS,
        RECORD_TYPE_PIPE,
        RECORD_TYPE_BINDING_PIPE,
        RECORD_TYPE_INTERPOLATE;

class DynamicProtoChangeDetector extends ProtoChangeDetector {
  PipeRegistry _pipeRegistry;
  ChangeDetectorDefinition definition;
  List<ProtoRecord> _records;
  DynamicProtoChangeDetector(this._pipeRegistry, this.definition) : super() {
    /* super call moved to initializer */;
    this._records = this._createRecords(definition);
  }
  instantiate(dynamic dispatcher) {
    return new DynamicChangeDetector(this.definition.strategy, dispatcher,
        this._pipeRegistry, this._records, this.definition.directiveRecords);
  }
  _createRecords(ChangeDetectorDefinition definition) {
    var recordBuilder = new ProtoRecordBuilder();
    ListWrapper.forEach(definition.bindingRecords, (b) {
      recordBuilder.addAst(b, definition.variableNames);
    });
    return coalesce(recordBuilder.records);
  }
}
num _jitProtoChangeDetectorClassCounter = 0;
class JitProtoChangeDetector extends ProtoChangeDetector {
  var _pipeRegistry;
  ChangeDetectorDefinition definition;
  Function _factory;
  JitProtoChangeDetector(this._pipeRegistry, this.definition) : super() {
    /* super call moved to initializer */;
    this._factory = this._createFactory(definition);
  }
  instantiate(dynamic dispatcher) {
    return this._factory(dispatcher, this._pipeRegistry);
  }
  _createFactory(ChangeDetectorDefinition definition) {
    var recordBuilder = new ProtoRecordBuilder();
    ListWrapper.forEach(definition.bindingRecords, (b) {
      recordBuilder.addAst(b, definition.variableNames);
    });
    var c = _jitProtoChangeDetectorClassCounter++;
    var records = coalesce(recordBuilder.records);
    var typeName = '''ChangeDetector${ c}''';
    return new ChangeDetectorJITGenerator(typeName, definition.strategy,
        records, this.definition.directiveRecords).generate();
  }
}
class ProtoRecordBuilder {
  List<ProtoRecord> records;
  ProtoRecordBuilder() {
    this.records = [];
  }
  addAst(BindingRecord b, [List<String> variableNames = null]) {
    var oldLast = ListWrapper.last(this.records);
    if (isPresent(oldLast) &&
        oldLast.bindingRecord.directiveRecord == b.directiveRecord) {
      oldLast.lastInDirective = false;
    }
    _ConvertAstIntoProtoRecords.append(this.records, b, variableNames);
    var newLast = ListWrapper.last(this.records);
    if (isPresent(newLast) && !identical(newLast, oldLast)) {
      newLast.lastInBinding = true;
      newLast.lastInDirective = true;
    }
  }
}
class _ConvertAstIntoProtoRecords {
  List<ProtoRecord> _records;
  BindingRecord _bindingRecord;
  String _expressionAsString;
  List<dynamic> _variableNames;
  _ConvertAstIntoProtoRecords(this._records, this._bindingRecord,
      this._expressionAsString, this._variableNames) {}
  static append(
      List<ProtoRecord> records, BindingRecord b, List<dynamic> variableNames) {
    var c = new _ConvertAstIntoProtoRecords(
        records, b, b.ast.toString(), variableNames);
    b.ast.visit(c);
  }
  visitImplicitReceiver(ImplicitReceiver ast) {
    return this._bindingRecord.implicitReceiver;
  }
  visitInterpolation(Interpolation ast) {
    var args = this._visitAll(ast.expressions);
    return this._addRecord(RECORD_TYPE_INTERPOLATE, "interpolate",
        _interpolationFn(ast.strings), args, ast.strings, 0);
  }
  visitLiteralPrimitive(LiteralPrimitive ast) {
    return this._addRecord(
        RECORD_TYPE_CONST, "literal", ast.value, [], null, 0);
  }
  visitAccessMember(AccessMember ast) {
    var receiver = ast.receiver.visit(this);
    if (isPresent(this._variableNames) &&
        ListWrapper.contains(this._variableNames, ast.name) &&
        ast.receiver is ImplicitReceiver) {
      return this._addRecord(
          RECORD_TYPE_LOCAL, ast.name, ast.name, [], null, receiver);
    } else {
      return this._addRecord(
          RECORD_TYPE_PROPERTY, ast.name, ast.getter, [], null, receiver);
    }
  }
  visitMethodCall(MethodCall ast) {
    var receiver = ast.receiver.visit(this);
    var args = this._visitAll(ast.args);
    if (isPresent(this._variableNames) &&
        ListWrapper.contains(this._variableNames, ast.name)) {
      var target = this._addRecord(
          RECORD_TYPE_LOCAL, ast.name, ast.name, [], null, receiver);
      return this._addRecord(
          RECORD_TYPE_INVOKE_CLOSURE, "closure", null, args, null, target);
    } else {
      return this._addRecord(
          RECORD_TYPE_INVOKE_METHOD, ast.name, ast.fn, args, null, receiver);
    }
  }
  visitFunctionCall(FunctionCall ast) {
    var target = ast.target.visit(this);
    var args = this._visitAll(ast.args);
    return this._addRecord(
        RECORD_TYPE_INVOKE_CLOSURE, "closure", null, args, null, target);
  }
  visitLiteralArray(LiteralArray ast) {
    var primitiveName = '''arrayFn${ ast . expressions . length}''';
    return this._addRecord(RECORD_TYPE_PRIMITIVE_OP, primitiveName,
        _arrayFn(ast.expressions.length), this._visitAll(ast.expressions), null,
        0);
  }
  visitLiteralMap(LiteralMap ast) {
    return this._addRecord(RECORD_TYPE_PRIMITIVE_OP,
        _mapPrimitiveName(ast.keys), ChangeDetectionUtil.mapFn(ast.keys),
        this._visitAll(ast.values), null, 0);
  }
  visitBinary(Binary ast) {
    var left = ast.left.visit(this);
    var right = ast.right.visit(this);
    return this._addRecord(RECORD_TYPE_PRIMITIVE_OP,
        _operationToPrimitiveName(ast.operation),
        _operationToFunction(ast.operation), [left, right], null, 0);
  }
  visitPrefixNot(PrefixNot ast) {
    var exp = ast.expression.visit(this);
    return this._addRecord(RECORD_TYPE_PRIMITIVE_OP, "operation_negate",
        ChangeDetectionUtil.operation_negate, [exp], null, 0);
  }
  visitConditional(Conditional ast) {
    var c = ast.condition.visit(this);
    var t = ast.trueExp.visit(this);
    var f = ast.falseExp.visit(this);
    return this._addRecord(RECORD_TYPE_PRIMITIVE_OP, "cond",
        ChangeDetectionUtil.cond, [c, t, f], null, 0);
  }
  visitPipe(Pipe ast) {
    var value = ast.exp.visit(this);
    var type = ast.inBinding ? RECORD_TYPE_BINDING_PIPE : RECORD_TYPE_PIPE;
    return this._addRecord(type, ast.name, ast.name, [], null, value);
  }
  visitKeyedAccess(KeyedAccess ast) {
    var obj = ast.obj.visit(this);
    var key = ast.key.visit(this);
    return this._addRecord(RECORD_TYPE_KEYED_ACCESS, "keyedAccess",
        ChangeDetectionUtil.keyedAccess, [key], null, obj);
  }
  _visitAll(List<dynamic> asts) {
    var res = ListWrapper.createFixedSize(asts.length);
    for (var i = 0; i < asts.length; ++i) {
      res[i] = asts[i].visit(this);
    }
    return res;
  }
  _addRecord(type, name, funcOrValue, args, fixedArgs, context) {
    var selfIndex = this._records.length + 1;
    if (context is DirectiveIndex) {
      ListWrapper.push(this._records, new ProtoRecord(type, name, funcOrValue,
          args, fixedArgs, -1, context, selfIndex, this._bindingRecord,
          this._expressionAsString, false, false));
    } else {
      ListWrapper.push(this._records, new ProtoRecord(type, name, funcOrValue,
          args, fixedArgs, context, null, selfIndex, this._bindingRecord,
          this._expressionAsString, false, false));
    }
    return selfIndex;
  }
}
Function _arrayFn(num length) {
  switch (length) {
    case 0:
      return ChangeDetectionUtil.arrayFn0;
    case 1:
      return ChangeDetectionUtil.arrayFn1;
    case 2:
      return ChangeDetectionUtil.arrayFn2;
    case 3:
      return ChangeDetectionUtil.arrayFn3;
    case 4:
      return ChangeDetectionUtil.arrayFn4;
    case 5:
      return ChangeDetectionUtil.arrayFn5;
    case 6:
      return ChangeDetectionUtil.arrayFn6;
    case 7:
      return ChangeDetectionUtil.arrayFn7;
    case 8:
      return ChangeDetectionUtil.arrayFn8;
    case 9:
      return ChangeDetectionUtil.arrayFn9;
    default:
      throw new BaseException(
          '''Does not support literal maps with more than 9 elements''');
  }
}
_mapPrimitiveName(List<dynamic> keys) {
  var stringifiedKeys = ListWrapper.join(
      ListWrapper.map(keys, (k) => isString(k) ? '''"${ k}"''' : '''${ k}'''),
      ", ");
  return '''mapFn([${ stringifiedKeys}])''';
}
String _operationToPrimitiveName(String operation) {
  switch (operation) {
    case "+":
      return "operation_add";
    case "-":
      return "operation_subtract";
    case "*":
      return "operation_multiply";
    case "/":
      return "operation_divide";
    case "%":
      return "operation_remainder";
    case "==":
      return "operation_equals";
    case "!=":
      return "operation_not_equals";
    case "===":
      return "operation_identical";
    case "!==":
      return "operation_not_identical";
    case "<":
      return "operation_less_then";
    case ">":
      return "operation_greater_then";
    case "<=":
      return "operation_less_or_equals_then";
    case ">=":
      return "operation_greater_or_equals_then";
    case "&&":
      return "operation_logical_and";
    case "||":
      return "operation_logical_or";
    default:
      throw new BaseException('''Unsupported operation ${ operation}''');
  }
}
Function _operationToFunction(String operation) {
  switch (operation) {
    case "+":
      return ChangeDetectionUtil.operation_add;
    case "-":
      return ChangeDetectionUtil.operation_subtract;
    case "*":
      return ChangeDetectionUtil.operation_multiply;
    case "/":
      return ChangeDetectionUtil.operation_divide;
    case "%":
      return ChangeDetectionUtil.operation_remainder;
    case "==":
      return ChangeDetectionUtil.operation_equals;
    case "!=":
      return ChangeDetectionUtil.operation_not_equals;
    case "===":
      return ChangeDetectionUtil.operation_identical;
    case "!==":
      return ChangeDetectionUtil.operation_not_identical;
    case "<":
      return ChangeDetectionUtil.operation_less_then;
    case ">":
      return ChangeDetectionUtil.operation_greater_then;
    case "<=":
      return ChangeDetectionUtil.operation_less_or_equals_then;
    case ">=":
      return ChangeDetectionUtil.operation_greater_or_equals_then;
    case "&&":
      return ChangeDetectionUtil.operation_logical_and;
    case "||":
      return ChangeDetectionUtil.operation_logical_or;
    default:
      throw new BaseException('''Unsupported operation ${ operation}''');
  }
}
s(v) {
  return isPresent(v) ? '''${ v}''' : "";
}
_interpolationFn(List<dynamic> strings) {
  var length = strings.length;
  var c0 = length > 0 ? strings[0] : null;
  var c1 = length > 1 ? strings[1] : null;
  var c2 = length > 2 ? strings[2] : null;
  var c3 = length > 3 ? strings[3] : null;
  var c4 = length > 4 ? strings[4] : null;
  var c5 = length > 5 ? strings[5] : null;
  var c6 = length > 6 ? strings[6] : null;
  var c7 = length > 7 ? strings[7] : null;
  var c8 = length > 8 ? strings[8] : null;
  var c9 = length > 9 ? strings[9] : null;
  switch (length - 1) {
    case 1:
      return (a1) => c0 + s(a1) + c1;
    case 2:
      return (a1, a2) => c0 + s(a1) + c1 + s(a2) + c2;
    case 3:
      return (a1, a2, a3) => c0 + s(a1) + c1 + s(a2) + c2 + s(a3) + c3;
    case 4:
      return (a1, a2, a3, a4) =>
          c0 + s(a1) + c1 + s(a2) + c2 + s(a3) + c3 + s(a4) + c4;
    case 5:
      return (a1, a2, a3, a4, a5) =>
          c0 + s(a1) + c1 + s(a2) + c2 + s(a3) + c3 + s(a4) + c4 + s(a5) + c5;
    case 6:
      return (a1, a2, a3, a4, a5, a6) => c0 +
          s(a1) +
          c1 +
          s(a2) +
          c2 +
          s(a3) +
          c3 +
          s(a4) +
          c4 +
          s(a5) +
          c5 +
          s(a6) +
          c6;
    case 7:
      return (a1, a2, a3, a4, a5, a6, a7) => c0 +
          s(a1) +
          c1 +
          s(a2) +
          c2 +
          s(a3) +
          c3 +
          s(a4) +
          c4 +
          s(a5) +
          c5 +
          s(a6) +
          c6 +
          s(a7) +
          c7;
    case 8:
      return (a1, a2, a3, a4, a5, a6, a7, a8) => c0 +
          s(a1) +
          c1 +
          s(a2) +
          c2 +
          s(a3) +
          c3 +
          s(a4) +
          c4 +
          s(a5) +
          c5 +
          s(a6) +
          c6 +
          s(a7) +
          c7 +
          s(a8) +
          c8;
    case 9:
      return (a1, a2, a3, a4, a5, a6, a7, a8, a9) => c0 +
          s(a1) +
          c1 +
          s(a2) +
          c2 +
          s(a3) +
          c3 +
          s(a4) +
          c4 +
          s(a5) +
          c5 +
          s(a6) +
          c6 +
          s(a7) +
          c7 +
          s(a8) +
          c8 +
          s(a9) +
          c9;
    default:
      throw new BaseException('''Does not support more than 9 expressions''');
  }
}
