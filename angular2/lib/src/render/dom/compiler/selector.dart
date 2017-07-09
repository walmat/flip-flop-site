library angular2.src.render.dom.compiler.selector;

import "package:angular2/src/facade/collection.dart"
    show List, Map, ListWrapper, MapWrapper;
import "package:angular2/src/facade/lang.dart"
    show
        isPresent,
        isBlank,
        RegExpWrapper,
        RegExpMatcherWrapper,
        StringWrapper,
        BaseException;

const _EMPTY_ATTR_VALUE = "";
// TODO: Can't use `const` here as

// in Dart this is not transpiled into `final` yet...
var _SELECTOR_REGEXP = RegExpWrapper.create("(\\:not\\()|" +
    "([-\\w]+)|" +
    "(?:\\.([-\\w]+))|" +
    "(?:\\[([-\\w*]+)(?:=([^\\]]*))?\\])|" +
    "(?:\\))|" +
    "(\\s*,\\s*)");
/**
 * A css selector contains an element name,
 * css classes and attribute/value pairs with the purpose
 * of selecting subsets out of them.
 */
class CssSelector {
  String element;
  List<String> classNames;
  List<String> attrs;
  CssSelector notSelector;
  static List<CssSelector> parse(String selector) {
    var results = ListWrapper.create();
    var _addResult = (res, cssSel) {
      if (isPresent(cssSel.notSelector) &&
          isBlank(cssSel.element) &&
          ListWrapper.isEmpty(cssSel.classNames) &&
          ListWrapper.isEmpty(cssSel.attrs)) {
        cssSel.element = "*";
      }
      ListWrapper.push(res, cssSel);
    };
    var cssSelector = new CssSelector();
    var matcher = RegExpWrapper.matcher(_SELECTOR_REGEXP, selector);
    var match;
    var current = cssSelector;
    while (isPresent(match = RegExpMatcherWrapper.next(matcher))) {
      if (isPresent(match[1])) {
        if (isPresent(cssSelector.notSelector)) {
          throw new BaseException("Nesting :not is not allowed in a selector");
        }
        current.notSelector = new CssSelector();
        current = current.notSelector;
      }
      if (isPresent(match[2])) {
        current.setElement(match[2]);
      }
      if (isPresent(match[3])) {
        current.addClassName(match[3]);
      }
      if (isPresent(match[4])) {
        current.addAttribute(match[4], match[5]);
      }
      if (isPresent(match[6])) {
        _addResult(results, cssSelector);
        cssSelector = current = new CssSelector();
      }
    }
    _addResult(results, cssSelector);
    return results;
  }
  CssSelector() {
    this.element = null;
    this.classNames = ListWrapper.create();
    this.attrs = ListWrapper.create();
    this.notSelector = null;
  }
  bool isElementSelector() {
    return isPresent(this.element) &&
        ListWrapper.isEmpty(this.classNames) &&
        ListWrapper.isEmpty(this.attrs) &&
        isBlank(this.notSelector);
  }
  setElement([String element = null]) {
    if (isPresent(element)) {
      element = element.toLowerCase();
    }
    this.element = element;
  }
  addAttribute(String name, [String value = _EMPTY_ATTR_VALUE]) {
    ListWrapper.push(this.attrs, name.toLowerCase());
    if (isPresent(value)) {
      value = value.toLowerCase();
    } else {
      value = _EMPTY_ATTR_VALUE;
    }
    ListWrapper.push(this.attrs, value);
  }
  addClassName(String name) {
    ListWrapper.push(this.classNames, name.toLowerCase());
  }
  String toString() {
    var res = "";
    if (isPresent(this.element)) {
      res += this.element;
    }
    if (isPresent(this.classNames)) {
      for (var i = 0; i < this.classNames.length; i++) {
        res += "." + this.classNames[i];
      }
    }
    if (isPresent(this.attrs)) {
      for (var i = 0; i < this.attrs.length;) {
        var attrName = this.attrs[i++];
        var attrValue = this.attrs[i++];
        res += "[" + attrName;
        if (attrValue.length > 0) {
          res += "=" + attrValue;
        }
        res += "]";
      }
    }
    if (isPresent(this.notSelector)) {
      res += ":not(" + this.notSelector.toString() + ")";
    }
    return res;
  }
}
/**
 * Reads a list of CssSelectors and allows to calculate which ones
 * are contained in a given CssSelector.
 */
class SelectorMatcher {
  static createNotMatcher(CssSelector notSelector) {
    var notMatcher = new SelectorMatcher();
    notMatcher._addSelectable(notSelector, null, null);
    return notMatcher;
  }
  Map<String, List<String>> _elementMap;
  Map<String, SelectorMatcher> _elementPartialMap;
  Map<String, List<String>> _classMap;
  Map<String, SelectorMatcher> _classPartialMap;
  Map<String, Map<String, List<String>>> _attrValueMap;
  Map<String, Map<String, SelectorMatcher>> _attrValuePartialMap;
  List<SelectorListContext> _listContexts;
  SelectorMatcher() {
    this._elementMap = MapWrapper.create();
    this._elementPartialMap = MapWrapper.create();
    this._classMap = MapWrapper.create();
    this._classPartialMap = MapWrapper.create();
    this._attrValueMap = MapWrapper.create();
    this._attrValuePartialMap = MapWrapper.create();
    this._listContexts = ListWrapper.create();
  }
  addSelectables(List<CssSelector> cssSelectors, dynamic callbackCtxt) {
    var listContext = null;
    if (cssSelectors.length > 1) {
      listContext = new SelectorListContext(cssSelectors);
      ListWrapper.push(this._listContexts, listContext);
    }
    for (var i = 0; i < cssSelectors.length; i++) {
      this._addSelectable(cssSelectors[i], callbackCtxt, listContext);
    }
  }
  /**
   * Add an object that can be found later on by calling `match`.
   * @param cssSelector A css selector
   * @param callbackCtxt An opaque object that will be given to the callback of the `match` function
   */
  _addSelectable(CssSelector cssSelector, dynamic callbackCtxt,
      SelectorListContext listContext) {
    var matcher = this;
    var element = cssSelector.element;
    var classNames = cssSelector.classNames;
    var attrs = cssSelector.attrs;
    var selectable =
        new SelectorContext(cssSelector, callbackCtxt, listContext);
    if (isPresent(element)) {
      var isTerminal =
          identical(attrs.length, 0) && identical(classNames.length, 0);
      if (isTerminal) {
        this._addTerminal(matcher._elementMap, element, selectable);
      } else {
        matcher = this._addPartial(matcher._elementPartialMap, element);
      }
    }
    if (isPresent(classNames)) {
      for (var index = 0; index < classNames.length; index++) {
        var isTerminal = identical(attrs.length, 0) &&
            identical(index, classNames.length - 1);
        var className = classNames[index];
        if (isTerminal) {
          this._addTerminal(matcher._classMap, className, selectable);
        } else {
          matcher = this._addPartial(matcher._classPartialMap, className);
        }
      }
    }
    if (isPresent(attrs)) {
      for (var index = 0; index < attrs.length;) {
        var isTerminal = identical(index, attrs.length - 2);
        var attrName = attrs[index++];
        var attrValue = attrs[index++];
        if (isTerminal) {
          var terminalMap = matcher._attrValueMap;
          var terminalValuesMap = MapWrapper.get(terminalMap, attrName);
          if (isBlank(terminalValuesMap)) {
            terminalValuesMap = MapWrapper.create();
            MapWrapper.set(terminalMap, attrName, terminalValuesMap);
          }
          this._addTerminal(terminalValuesMap, attrValue, selectable);
        } else {
          var parttialMap = matcher._attrValuePartialMap;
          var partialValuesMap = MapWrapper.get(parttialMap, attrName);
          if (isBlank(partialValuesMap)) {
            partialValuesMap = MapWrapper.create();
            MapWrapper.set(parttialMap, attrName, partialValuesMap);
          }
          matcher = this._addPartial(partialValuesMap, attrValue);
        }
      }
    }
  }
  _addTerminal(
      Map<String, List<String>> map, String name, SelectorContext selectable) {
    var terminalList = MapWrapper.get(map, name);
    if (isBlank(terminalList)) {
      terminalList = ListWrapper.create();
      MapWrapper.set(map, name, terminalList);
    }
    ListWrapper.push(terminalList, selectable);
  }
  SelectorMatcher _addPartial(Map<String, SelectorMatcher> map, String name) {
    var matcher = MapWrapper.get(map, name);
    if (isBlank(matcher)) {
      matcher = new SelectorMatcher();
      MapWrapper.set(map, name, matcher);
    }
    return matcher;
  }
  /**
   * Find the objects that have been added via `addSelectable`
   * whose css selector is contained in the given css selector.
   * @param cssSelector A css selector
   * @param matchedCallback This callback will be called with the object handed into `addSelectable`
   * @return boolean true if a match was found
  */
  bool match(CssSelector cssSelector, matchedCallback) {
    var result = false;
    var element = cssSelector.element;
    var classNames = cssSelector.classNames;
    var attrs = cssSelector.attrs;
    for (var i = 0; i < this._listContexts.length; i++) {
      this._listContexts[i].alreadyMatched = false;
    }
    result = this._matchTerminal(
            this._elementMap, element, cssSelector, matchedCallback) ||
        result;
    result = this._matchPartial(
            this._elementPartialMap, element, cssSelector, matchedCallback) ||
        result;
    if (isPresent(classNames)) {
      for (var index = 0; index < classNames.length; index++) {
        var className = classNames[index];
        result = this._matchTerminal(
                this._classMap, className, cssSelector, matchedCallback) ||
            result;
        result = this._matchPartial(this._classPartialMap, className,
                cssSelector, matchedCallback) ||
            result;
      }
    }
    if (isPresent(attrs)) {
      for (var index = 0; index < attrs.length;) {
        var attrName = attrs[index++];
        var attrValue = attrs[index++];
        var terminalValuesMap = MapWrapper.get(this._attrValueMap, attrName);
        if (!StringWrapper.equals(attrValue, _EMPTY_ATTR_VALUE)) {
          result = this._matchTerminal(terminalValuesMap, _EMPTY_ATTR_VALUE,
                  cssSelector, matchedCallback) ||
              result;
        }
        result = this._matchTerminal(
                terminalValuesMap, attrValue, cssSelector, matchedCallback) ||
            result;
        var partialValuesMap =
            MapWrapper.get(this._attrValuePartialMap, attrName);
        result = this._matchPartial(
                partialValuesMap, attrValue, cssSelector, matchedCallback) ||
            result;
      }
    }
    return result;
  }
  bool _matchTerminal(Map<String, List<String>> map, name,
      CssSelector cssSelector, matchedCallback) {
    if (isBlank(map) || isBlank(name)) {
      return false;
    }
    var selectables = MapWrapper.get(map, name);
    var starSelectables = MapWrapper.get(map, "*");
    if (isPresent(starSelectables)) {
      selectables = ListWrapper.concat(selectables, starSelectables);
    }
    if (isBlank(selectables)) {
      return false;
    }
    var selectable;
    var result = false;
    for (var index = 0; index < selectables.length; index++) {
      selectable = selectables[index];
      result = selectable.finalize(cssSelector, matchedCallback) || result;
    }
    return result;
  }
  bool _matchPartial(Map<String, SelectorMatcher> map, name,
      CssSelector cssSelector, matchedCallback) {
    if (isBlank(map) || isBlank(name)) {
      return false;
    }
    var nestedSelector = MapWrapper.get(map, name);
    if (isBlank(nestedSelector)) {
      return false;
    }
    // TODO(perf): get rid of recursion and measure again

    // TODO(perf): don't pass the whole selector into the recursion,

    // but only the not processed parts
    return nestedSelector.match(cssSelector, matchedCallback);
  }
}
class SelectorListContext {
  List<CssSelector> selectors;
  bool alreadyMatched;
  SelectorListContext(List<CssSelector> selectors) {
    this.selectors = selectors;
    this.alreadyMatched = false;
  }
}
// Store context to pass back selector and context when a selector is matched
class SelectorContext {
  CssSelector selector;
  CssSelector notSelector;
  var cbContext;
  SelectorListContext listContext;
  SelectorContext(CssSelector selector, dynamic cbContext,
      SelectorListContext listContext) {
    this.selector = selector;
    this.notSelector = selector.notSelector;
    this.cbContext = cbContext;
    this.listContext = listContext;
  }
  finalize(CssSelector cssSelector, callback) {
    var result = true;
    if (isPresent(this.notSelector) &&
        (isBlank(this.listContext) || !this.listContext.alreadyMatched)) {
      var notMatcher = SelectorMatcher.createNotMatcher(this.notSelector);
      result = !notMatcher.match(cssSelector, null);
    }
    if (result &&
        isPresent(callback) &&
        (isBlank(this.listContext) || !this.listContext.alreadyMatched)) {
      if (isPresent(this.listContext)) {
        this.listContext.alreadyMatched = true;
      }
      callback(this.selector, this.cbContext);
    }
    return result;
  }
}
