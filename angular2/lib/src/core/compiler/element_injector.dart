library angular2.src.core.compiler.element_injector;

import "package:angular2/src/facade/lang.dart"
    show isPresent, isBlank, Type, int, BaseException, stringify;
import "package:angular2/src/facade/async.dart"
    show EventEmitter, ObservableWrapper;
import "package:angular2/src/facade/collection.dart"
    show List, ListWrapper, MapWrapper, StringMapWrapper;
import "package:angular2/di.dart"
    show
        Injector,
        Key,
        Dependency,
        bind,
        Binding,
        ResolvedBinding,
        NoBindingError,
        AbstractBindingError,
        CyclicDependencyError,
        resolveForwardRef,
        resolveBindings;
import "package:angular2/src/core/annotations_impl/visibility.dart"
    show Visibility, self;
import "package:angular2/src/core/annotations_impl/di.dart"
    show Attribute, Query;
import "view.dart" as viewModule;
import "view_manager.dart" as avmModule;
import "view_container_ref.dart" show ViewContainerRef;
import "element_ref.dart" show ElementRef;
import "view_ref.dart" show ProtoViewRef, ViewRef;
import "package:angular2/src/core/annotations_impl/annotations.dart"
    show Directive, Component, onChange, onDestroy, onAllChangesDone;
import "package:angular2/change_detection.dart"
    show ChangeDetector, ChangeDetectorRef;
import "query_list.dart" show QueryList;
import "package:angular2/src/reflection/reflection.dart" show reflector;
import "package:angular2/src/render/api.dart" show DirectiveMetadata;

var _MAX_DIRECTIVE_CONSTRUCTION_COUNTER = 10;
var _undefined = new Object();
var _staticKeys;
class StaticKeys {
  num viewManagerId;
  num protoViewId;
  num viewContainerId;
  num changeDetectorRefId;
  num elementRefId;
  StaticKeys() {
    // TODO: vsavkin Key.annotate(Key.get(AppView), 'static')
    this.viewManagerId = Key.get(avmModule.AppViewManager).id;
    this.protoViewId = Key.get(ProtoViewRef).id;
    this.viewContainerId = Key.get(ViewContainerRef).id;
    this.changeDetectorRefId = Key.get(ChangeDetectorRef).id;
    this.elementRefId = Key.get(ElementRef).id;
  }
  static StaticKeys instance() {
    if (isBlank(_staticKeys)) _staticKeys = new StaticKeys();
    return _staticKeys;
  }
}
class TreeNode<T extends TreeNode<dynamic>> {
  T _parent;
  T _head;
  T _tail;
  T _next;
  TreeNode(T parent) {
    this._head = null;
    this._tail = null;
    this._next = null;
    if (isPresent(parent)) parent.addChild(this);
  }
  void _assertConsistency() {
    this._assertHeadBeforeTail();
    this._assertTailReachable();
    this._assertPresentInParentList();
  }
  void _assertHeadBeforeTail() {
    if (isBlank(this._tail) && isPresent(this._head)) throw new BaseException(
        "null tail but non-null head");
  }
  void _assertTailReachable() {
    if (isBlank(this._tail)) return;
    if (isPresent(this._tail._next)) throw new BaseException("node after tail");
    var p = this._head;
    while (isPresent(p) && p != this._tail) p = p._next;
    if (isBlank(p) &&
        isPresent(this._tail)) throw new BaseException("tail not reachable.");
  }
  void _assertPresentInParentList() {
    var p = this._parent;
    if (isBlank(p)) {
      return;
    }
    var cur = p._head;
    while (isPresent(cur) && cur != this) cur = cur._next;
    if (isBlank(cur)) throw new BaseException(
        "node not reachable through parent.");
  }
  /**
   * Adds a child to the parent node. The child MUST NOT be a part of a tree.
   */
  void addChild(T child) {
    if (isPresent(this._tail)) {
      this._tail._next = child;
      this._tail = child;
    } else {
      this._tail = this._head = child;
    }
    child._next = null;
    child._parent = this;
    this._assertConsistency();
  }
  /**
   * Adds a child to the parent node after a given sibling.
   * The child MUST NOT be a part of a tree and the sibling must be present.
   */
  void addChildAfter(T child, T prevSibling) {
    this._assertConsistency();
    if (isBlank(prevSibling)) {
      var prevHead = this._head;
      this._head = child;
      child._next = prevHead;
      if (isBlank(this._tail)) this._tail = child;
    } else if (isBlank(prevSibling._next)) {
      this.addChild(child);
      return;
    } else {
      prevSibling._assertPresentInParentList();
      child._next = prevSibling._next;
      prevSibling._next = child;
    }
    child._parent = this;
    this._assertConsistency();
  }
  /**
   * Detaches a node from the parent's tree.
   */
  void remove() {
    this._assertConsistency();
    if (isBlank(this.parent)) return;
    var nextSibling = this._next;
    var prevSibling = this._findPrev();
    if (isBlank(prevSibling)) {
      this.parent._head = this._next;
    } else {
      prevSibling._next = this._next;
    }
    if (isBlank(nextSibling)) {
      this._parent._tail = prevSibling;
    }
    this._parent._assertConsistency();
    this._parent = null;
    this._next = null;
    this._assertConsistency();
  }
  /**
   * Finds a previous sibling or returns null if first child.
   * Assumes the node has a parent.
   * TODO(rado): replace with DoublyLinkedList to avoid O(n) here.
   */
  _findPrev() {
    var node = this.parent._head;
    if (node == this) return null;
    while (!identical(node._next, this)) node = node._next;
    return node;
  }
  get parent {
    return this._parent;
  }
  // TODO(rado): replace with a function call, does too much work for a getter.
  get children {
    var res = [];
    var child = this._head;
    while (child != null) {
      ListWrapper.push(res, child);
      child = child._next;
    }
    return res;
  }
}
class DirectiveDependency extends Dependency {
  Visibility visibility;
  String attributeName;
  var queryDirective;
  DirectiveDependency(Key key, bool asPromise, bool lazy, bool optional,
      List<dynamic> properties, this.visibility, this.attributeName,
      this.queryDirective)
      : super(key, asPromise, lazy, optional, properties) {
    /* super call moved to initializer */;
    this._verify();
  }
  void _verify() {
    var count = 0;
    if (isPresent(this.queryDirective)) count++;
    if (isPresent(this.attributeName)) count++;
    if (count > 1) throw new BaseException(
        "A directive injectable can contain only one of the following @Attribute or @Query.");
  }
  static Dependency createFrom(Dependency d) {
    return new DirectiveDependency(d.key, d.asPromise, d.lazy, d.optional,
        d.properties, DirectiveDependency._visibility(d.properties),
        DirectiveDependency._attributeName(d.properties),
        DirectiveDependency._query(d.properties));
  }
  static Visibility _visibility(properties) {
    if (properties.length == 0) return self;
    var p = ListWrapper.find(properties, (p) => p is Visibility);
    return isPresent(p) ? p : self;
  }
  static String _attributeName(properties) {
    var p = ListWrapper.find(properties, (p) => p is Attribute);
    return isPresent(p) ? p.attributeName : null;
  }
  static _query(properties) {
    var p = ListWrapper.find(properties, (p) => p is Query);
    return isPresent(p) ? resolveForwardRef(p.directive) : null;
  }
}
class DirectiveBinding extends ResolvedBinding {
  List<ResolvedBinding> resolvedAppInjectables;
  List<ResolvedBinding> resolvedHostInjectables;
  List<ResolvedBinding> resolvedViewInjectables;
  DirectiveMetadata metadata;
  DirectiveBinding(Key key, Function factory, List<Dependency> dependencies,
      bool providedAsPromise, this.resolvedAppInjectables,
      this.resolvedHostInjectables, this.resolvedViewInjectables, this.metadata)
      : super(key, factory, dependencies, providedAsPromise) {
    /* super call moved to initializer */;
  }
  get callOnDestroy {
    return this.metadata.callOnDestroy;
  }
  get callOnChange {
    return this.metadata.callOnChange;
  }
  get callOnAllChangesDone {
    return this.metadata.callOnAllChangesDone;
  }
  get displayName {
    return this.key.displayName;
  }
  List<String> get eventEmitters {
    return isPresent(this.metadata) && isPresent(this.metadata.events)
        ? this.metadata.events
        : [];
  }
  Map<String, String> get hostActions {
    return isPresent(this.metadata) && isPresent(this.metadata.hostActions)
        ? this.metadata.hostActions
        : MapWrapper.create();
  }
  get changeDetection {
    return this.metadata.changeDetection;
  }
  static DirectiveBinding createFromBinding(Binding binding, Directive ann) {
    if (isBlank(ann)) {
      ann = new Directive();
    }
    var rb = binding.resolve();
    var deps = ListWrapper.map(rb.dependencies, DirectiveDependency.createFrom);
    var resolvedAppInjectables = ann is Component && isPresent(ann.appInjector)
        ? Injector.resolve(ann.appInjector)
        : [];
    var resolvedHostInjectables =
        isPresent(ann.hostInjector) ? resolveBindings(ann.hostInjector) : [];
    var resolvedViewInjectables = ann is Component &&
        isPresent(ann.viewInjector) ? resolveBindings(ann.viewInjector) : [];
    var metadata = new DirectiveMetadata(
        id: stringify(rb.key.token),
        type: ann is Component
            ? DirectiveMetadata.COMPONENT_TYPE
            : DirectiveMetadata.DIRECTIVE_TYPE,
        selector: ann.selector,
        compileChildren: ann.compileChildren,
        events: ann.events,
        hostListeners: isPresent(ann.hostListeners)
            ? MapWrapper.createFromStringMap(ann.hostListeners)
            : null,
        hostProperties: isPresent(ann.hostProperties)
            ? MapWrapper.createFromStringMap(ann.hostProperties)
            : null,
        hostAttributes: isPresent(ann.hostAttributes)
            ? MapWrapper.createFromStringMap(ann.hostAttributes)
            : null,
        hostActions: isPresent(ann.hostActions)
            ? MapWrapper.createFromStringMap(ann.hostActions)
            : null,
        properties: isPresent(ann.properties)
            ? MapWrapper.createFromStringMap(ann.properties)
            : null,
        readAttributes: DirectiveBinding._readAttributes(deps),
        callOnDestroy: ann.hasLifecycleHook(onDestroy),
        callOnChange: ann.hasLifecycleHook(onChange),
        callOnAllChangesDone: ann.hasLifecycleHook(onAllChangesDone),
        changeDetection: ann is Component ? ann.changeDetection : null);
    return new DirectiveBinding(rb.key, rb.factory, deps, rb.providedAsPromise,
        resolvedAppInjectables, resolvedHostInjectables,
        resolvedViewInjectables, metadata);
  }
  static _readAttributes(deps) {
    var readAttributes = [];
    ListWrapper.forEach(deps, (dep) {
      if (isPresent(dep.attributeName)) {
        ListWrapper.push(readAttributes, dep.attributeName);
      }
    });
    return readAttributes;
  }
  static DirectiveBinding createFromType(Type type, Directive annotation) {
    var binding = new Binding(type, toClass: type);
    return DirectiveBinding.createFromBinding(binding, annotation);
  }
}
// TODO(rado): benchmark and consider rolling in as ElementInjector fields.
class PreBuiltObjects {
  avmModule.AppViewManager viewManager;
  viewModule.AppView view;
  viewModule.AppProtoView protoView;
  PreBuiltObjects(this.viewManager, this.view, this.protoView) {}
}
class EventEmitterAccessor {
  String eventName;
  Function getter;
  EventEmitterAccessor(this.eventName, this.getter) {}
  subscribe(viewModule.AppView view, num boundElementIndex, Object directive) {
    var eventEmitter = this.getter(directive);
    return ObservableWrapper.subscribe(eventEmitter, (eventObj) =>
        view.triggerEventHandlers(this.eventName, eventObj, boundElementIndex));
  }
}
class HostActionAccessor {
  String actionExpression;
  Function getter;
  HostActionAccessor(this.actionExpression, this.getter) {}
  subscribe(viewModule.AppView view, num boundElementIndex, Object directive) {
    var eventEmitter = this.getter(directive);
    return ObservableWrapper.subscribe(eventEmitter, (actionObj) =>
        view.callAction(boundElementIndex, this.actionExpression, actionObj));
  }
}
const LIGHT_DOM = 1;
const SHADOW_DOM = 2;
const LIGHT_DOM_AND_SHADOW_DOM = 3;
class BindingData {
  ResolvedBinding binding;
  num visibility;
  BindingData(this.binding, this.visibility) {}
  getKeyId() {
    return this.binding.key.id;
  }
  createEventEmitterAccessors() {
    if (!(this.binding is DirectiveBinding)) return [];
    var db = (this.binding as DirectiveBinding);
    return ListWrapper.map(db.eventEmitters, (eventName) =>
        new EventEmitterAccessor(eventName, reflector.getter(eventName)));
  }
  createHostActionAccessors() {
    if (!(this.binding is DirectiveBinding)) return [];
    var res = [];
    var db = (this.binding as DirectiveBinding);
    MapWrapper.forEach(db.hostActions, (actionExpression, actionName) {
      ListWrapper.push(res, new HostActionAccessor(
          actionExpression, reflector.getter(actionName)));
    });
    return res;
  }
}
/**

Difference between di.Injector and ElementInjector

di.Injector:
 - imperative based (can create child injectors imperativly)
 - Lazy loading of code
 - Component/App Level services which are usually not DOM Related.


ElementInjector:
  - ProtoBased (Injector structure fixed at compile time)
  - understands @Ancestor, @Parent, @Child, @Descendent
  - Fast
  - Query mechanism for children
  - 1:1 to DOM structure.

 PERF BENCHMARK:
http://www.williambrownstreet.net/blog/2014/04/faster-angularjs-rendering-angularjs-and-reactjs/
 */
class ProtoElementInjector {
  // only _binding0 can contain a component
  ResolvedBinding _binding0;
  ResolvedBinding _binding1;
  ResolvedBinding _binding2;
  ResolvedBinding _binding3;
  ResolvedBinding _binding4;
  ResolvedBinding _binding5;
  ResolvedBinding _binding6;
  ResolvedBinding _binding7;
  ResolvedBinding _binding8;
  ResolvedBinding _binding9;
  int _keyId0;
  int _keyId1;
  int _keyId2;
  int _keyId3;
  int _keyId4;
  int _keyId5;
  int _keyId6;
  int _keyId7;
  int _keyId8;
  int _keyId9;
  num _visibility0;
  num _visibility1;
  num _visibility2;
  num _visibility3;
  num _visibility4;
  num _visibility5;
  num _visibility6;
  num _visibility7;
  num _visibility8;
  num _visibility9;
  ProtoElementInjector parent;
  int index;
  viewModule.AppView view;
  num distanceToParent;
  Map<String, String> attributes;
  List<List<EventEmitterAccessor>> eventEmitterAccessors;
  List<List<HostActionAccessor>> hostActionAccessors;
  /** Whether the element is exported as $implicit. */
  bool exportElement;
  /** Whether the component instance is exported as $implicit. */
  bool exportComponent;
  /** The variable name that will be set to $implicit for the element. */
  String exportImplicitName;
  bool _firstBindingIsComponent;
  static create(ProtoElementInjector parent, int index,
      List<ResolvedBinding> bindings, bool firstBindingIsComponent,
      num distanceToParent) {
    var bd = [];
    ProtoElementInjector._createDirectiveBindingData(
        bindings, bd, firstBindingIsComponent);
    ProtoElementInjector._createHostInjectorBindingData(bindings, bd);
    if (firstBindingIsComponent) {
      ProtoElementInjector._createViewInjectorBindingData(bindings, bd);
    }
    return new ProtoElementInjector(
        parent, index, bd, distanceToParent, firstBindingIsComponent);
  }
  static _createDirectiveBindingData(List<ResolvedBinding> bindings,
      List<BindingData> bd, bool firstBindingIsComponent) {
    if (firstBindingIsComponent) {
      ListWrapper.push(
          bd, new BindingData(bindings[0], LIGHT_DOM_AND_SHADOW_DOM));
      for (var i = 1; i < bindings.length; ++i) {
        ListWrapper.push(bd, new BindingData(bindings[i], LIGHT_DOM));
      }
    } else {
      ListWrapper.forEach(bindings, (b) {
        ListWrapper.push(bd, new BindingData(b, LIGHT_DOM));
      });
    }
  }
  static _createHostInjectorBindingData(
      List<ResolvedBinding> bindings, List<BindingData> bd) {
    ListWrapper.forEach(bindings, (b) {
      ListWrapper.forEach(b.resolvedHostInjectables, (b) {
        ListWrapper.push(bd, new BindingData(b, LIGHT_DOM));
      });
    });
  }
  static _createViewInjectorBindingData(
      List<ResolvedBinding> bindings, List<BindingData> bd) {
    var db = (bindings[0] as DirectiveBinding);
    ListWrapper.forEach(db.resolvedViewInjectables,
        (b) => ListWrapper.push(bd, new BindingData(b, SHADOW_DOM)));
  }
  ProtoElementInjector(ProtoElementInjector parent, int index,
      List<BindingData> bd, num distanceToParent,
      bool firstBindingIsComponent) {
    this.parent = parent;
    this.index = index;
    this.distanceToParent = distanceToParent;
    this.exportComponent = false;
    this.exportElement = false;
    this._firstBindingIsComponent = firstBindingIsComponent;
    this._binding0 = null;
    this._keyId0 = null;
    this._visibility0 = null;
    this._binding1 = null;
    this._keyId1 = null;
    this._visibility1 = null;
    this._binding2 = null;
    this._keyId2 = null;
    this._visibility2 = null;
    this._binding3 = null;
    this._keyId3 = null;
    this._visibility3 = null;
    this._binding4 = null;
    this._keyId4 = null;
    this._visibility4 = null;
    this._binding5 = null;
    this._keyId5 = null;
    this._visibility5 = null;
    this._binding6 = null;
    this._keyId6 = null;
    this._visibility6 = null;
    this._binding7 = null;
    this._keyId7 = null;
    this._visibility7 = null;
    this._binding8 = null;
    this._keyId8 = null;
    this._visibility8 = null;
    this._binding9 = null;
    this._keyId9 = null;
    this._visibility9 = null;
    var length = bd.length;
    this.eventEmitterAccessors = ListWrapper.createFixedSize(length);
    this.hostActionAccessors = ListWrapper.createFixedSize(length);
    if (length > 0) {
      this._binding0 = bd[0].binding;
      this._keyId0 = bd[0].getKeyId();
      this._visibility0 = bd[0].visibility;
      this.eventEmitterAccessors[0] = bd[0].createEventEmitterAccessors();
      this.hostActionAccessors[0] = bd[0].createHostActionAccessors();
    }
    if (length > 1) {
      this._binding1 = bd[1].binding;
      this._keyId1 = bd[1].getKeyId();
      this._visibility1 = bd[1].visibility;
      this.eventEmitterAccessors[1] = bd[1].createEventEmitterAccessors();
      this.hostActionAccessors[1] = bd[1].createHostActionAccessors();
    }
    if (length > 2) {
      this._binding2 = bd[2].binding;
      this._keyId2 = bd[2].getKeyId();
      this._visibility2 = bd[2].visibility;
      this.eventEmitterAccessors[2] = bd[2].createEventEmitterAccessors();
      this.hostActionAccessors[2] = bd[2].createHostActionAccessors();
    }
    if (length > 3) {
      this._binding3 = bd[3].binding;
      this._keyId3 = bd[3].getKeyId();
      this._visibility3 = bd[3].visibility;
      this.eventEmitterAccessors[3] = bd[3].createEventEmitterAccessors();
      this.hostActionAccessors[3] = bd[3].createHostActionAccessors();
    }
    if (length > 4) {
      this._binding4 = bd[4].binding;
      this._keyId4 = bd[4].getKeyId();
      this._visibility4 = bd[4].visibility;
      this.eventEmitterAccessors[4] = bd[4].createEventEmitterAccessors();
      this.hostActionAccessors[4] = bd[4].createHostActionAccessors();
    }
    if (length > 5) {
      this._binding5 = bd[5].binding;
      this._keyId5 = bd[5].getKeyId();
      this._visibility5 = bd[5].visibility;
      this.eventEmitterAccessors[5] = bd[5].createEventEmitterAccessors();
      this.hostActionAccessors[5] = bd[5].createHostActionAccessors();
    }
    if (length > 6) {
      this._binding6 = bd[6].binding;
      this._keyId6 = bd[6].getKeyId();
      this._visibility6 = bd[6].visibility;
      this.eventEmitterAccessors[6] = bd[6].createEventEmitterAccessors();
      this.hostActionAccessors[6] = bd[6].createHostActionAccessors();
    }
    if (length > 7) {
      this._binding7 = bd[7].binding;
      this._keyId7 = bd[7].getKeyId();
      this._visibility7 = bd[7].visibility;
      this.eventEmitterAccessors[7] = bd[7].createEventEmitterAccessors();
      this.hostActionAccessors[7] = bd[7].createHostActionAccessors();
    }
    if (length > 8) {
      this._binding8 = bd[8].binding;
      this._keyId8 = bd[8].getKeyId();
      this._visibility8 = bd[8].visibility;
      this.eventEmitterAccessors[8] = bd[8].createEventEmitterAccessors();
      this.hostActionAccessors[8] = bd[8].createHostActionAccessors();
    }
    if (length > 9) {
      this._binding9 = bd[9].binding;
      this._keyId9 = bd[9].getKeyId();
      this._visibility9 = bd[9].visibility;
      this.eventEmitterAccessors[9] = bd[9].createEventEmitterAccessors();
      this.hostActionAccessors[9] = bd[9].createHostActionAccessors();
    }
    if (length > 10) {
      throw "Maximum number of directives per element has been reached.";
    }
  }
  ElementInjector instantiate(ElementInjector parent) {
    return new ElementInjector(this, parent);
  }
  ProtoElementInjector directParent() {
    return this.distanceToParent < 2 ? this.parent : null;
  }
  bool get hasBindings {
    return isPresent(this._binding0);
  }
  getBindingAtIndex(int index) {
    if (index == 0) return this._binding0;
    if (index == 1) return this._binding1;
    if (index == 2) return this._binding2;
    if (index == 3) return this._binding3;
    if (index == 4) return this._binding4;
    if (index == 5) return this._binding5;
    if (index == 6) return this._binding6;
    if (index == 7) return this._binding7;
    if (index == 8) return this._binding8;
    if (index == 9) return this._binding9;
    throw new OutOfBoundsAccess(index);
  }
}
class ElementInjector extends TreeNode<ElementInjector> {
  ProtoElementInjector _proto;
  Injector _lightDomAppInjector;
  Injector _shadowDomAppInjector;
  ElementInjector _host;
  // If this element injector has a component, the component instance will be stored in _obj0
  dynamic _obj0;
  dynamic _obj1;
  dynamic _obj2;
  dynamic _obj3;
  dynamic _obj4;
  dynamic _obj5;
  dynamic _obj6;
  dynamic _obj7;
  dynamic _obj8;
  dynamic _obj9;
  var _preBuiltObjects;
  var _constructionCounter;
  dynamic _dynamicallyCreatedComponent;
  DirectiveBinding _dynamicallyCreatedComponentBinding;
  // Queries are added during construction or linking with a new parent.

  // They are never removed.
  QueryRef _query0;
  QueryRef _query1;
  QueryRef _query2;
  ElementInjector(ProtoElementInjector proto, ElementInjector parent)
      : super(parent) {
    /* super call moved to initializer */;
    this._proto = proto;
    // we cannot call dehydrate because fields won't be detected
    this._preBuiltObjects = null;
    this._lightDomAppInjector = null;
    this._shadowDomAppInjector = null;
    this._obj0 = null;
    this._obj1 = null;
    this._obj2 = null;
    this._obj3 = null;
    this._obj4 = null;
    this._obj5 = null;
    this._obj6 = null;
    this._obj7 = null;
    this._obj8 = null;
    this._obj9 = null;
    this._constructionCounter = 0;
    this._inheritQueries(parent);
    this._buildQueries();
  }
  dehydrate() {
    this._host = null;
    this._preBuiltObjects = null;
    this._lightDomAppInjector = null;
    this._shadowDomAppInjector = null;
    var p = this._proto;
    if (p._binding0 is DirectiveBinding &&
        ((p._binding0 as DirectiveBinding)).callOnDestroy) {
      this._obj0.onDestroy();
    }
    if (p._binding1 is DirectiveBinding &&
        ((p._binding1 as DirectiveBinding)).callOnDestroy) {
      this._obj1.onDestroy();
    }
    if (p._binding2 is DirectiveBinding &&
        ((p._binding2 as DirectiveBinding)).callOnDestroy) {
      this._obj2.onDestroy();
    }
    if (p._binding3 is DirectiveBinding &&
        ((p._binding3 as DirectiveBinding)).callOnDestroy) {
      this._obj3.onDestroy();
    }
    if (p._binding4 is DirectiveBinding &&
        ((p._binding4 as DirectiveBinding)).callOnDestroy) {
      this._obj4.onDestroy();
    }
    if (p._binding5 is DirectiveBinding &&
        ((p._binding5 as DirectiveBinding)).callOnDestroy) {
      this._obj5.onDestroy();
    }
    if (p._binding6 is DirectiveBinding &&
        ((p._binding6 as DirectiveBinding)).callOnDestroy) {
      this._obj6.onDestroy();
    }
    if (p._binding7 is DirectiveBinding &&
        ((p._binding7 as DirectiveBinding)).callOnDestroy) {
      this._obj7.onDestroy();
    }
    if (p._binding8 is DirectiveBinding &&
        ((p._binding8 as DirectiveBinding)).callOnDestroy) {
      this._obj8.onDestroy();
    }
    if (p._binding9 is DirectiveBinding &&
        ((p._binding9 as DirectiveBinding)).callOnDestroy) {
      this._obj9.onDestroy();
    }
    if (isPresent(this._dynamicallyCreatedComponentBinding) &&
        this._dynamicallyCreatedComponentBinding.callOnDestroy) {
      this._dynamicallyCreatedComponent.onDestroy();
    }
    this._obj0 = null;
    this._obj1 = null;
    this._obj2 = null;
    this._obj3 = null;
    this._obj4 = null;
    this._obj5 = null;
    this._obj6 = null;
    this._obj7 = null;
    this._obj8 = null;
    this._obj9 = null;
    this._dynamicallyCreatedComponent = null;
    this._dynamicallyCreatedComponentBinding = null;
    this._constructionCounter = 0;
  }
  hydrate(Injector injector, ElementInjector host,
      PreBuiltObjects preBuiltObjects) {
    var p = this._proto;
    this._host = host;
    this._lightDomAppInjector = injector;
    this._preBuiltObjects = preBuiltObjects;
    if (p._firstBindingIsComponent) {
      this._shadowDomAppInjector = this._createShadowDomAppInjector(
          (p._binding0 as DirectiveBinding), injector);
    }
    this._checkShadowDomAppInjector(this._shadowDomAppInjector);
    if (isPresent(p._keyId0)) this._getObjByKeyId(
        p._keyId0, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId1)) this._getObjByKeyId(
        p._keyId1, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId2)) this._getObjByKeyId(
        p._keyId2, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId3)) this._getObjByKeyId(
        p._keyId3, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId4)) this._getObjByKeyId(
        p._keyId4, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId5)) this._getObjByKeyId(
        p._keyId5, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId6)) this._getObjByKeyId(
        p._keyId6, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId7)) this._getObjByKeyId(
        p._keyId7, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId8)) this._getObjByKeyId(
        p._keyId8, LIGHT_DOM_AND_SHADOW_DOM);
    if (isPresent(p._keyId9)) this._getObjByKeyId(
        p._keyId9, LIGHT_DOM_AND_SHADOW_DOM);
  }
  _createShadowDomAppInjector(
      DirectiveBinding componentDirective, Injector appInjector) {
    if (!ListWrapper.isEmpty(componentDirective.resolvedAppInjectables)) {
      return appInjector
          .createChildFromResolved(componentDirective.resolvedAppInjectables);
    } else {
      return appInjector;
    }
  }
  dynamicallyCreateComponent(
      DirectiveBinding componentDirective, Injector parentInjector) {
    this._shadowDomAppInjector =
        this._createShadowDomAppInjector(componentDirective, parentInjector);
    this._dynamicallyCreatedComponentBinding = componentDirective;
    this._dynamicallyCreatedComponent =
        this._new(this._dynamicallyCreatedComponentBinding);
    return this._dynamicallyCreatedComponent;
  }
  _checkShadowDomAppInjector(Injector shadowDomAppInjector) {
    if (this._proto._firstBindingIsComponent && isBlank(shadowDomAppInjector)) {
      throw new BaseException(
          "A shadowDomAppInjector is required as this ElementInjector contains a component");
    } else if (!this._proto._firstBindingIsComponent &&
        isPresent(shadowDomAppInjector)) {
      throw new BaseException(
          "No shadowDomAppInjector allowed as there is not component stored in this ElementInjector");
    }
  }
  get(token) {
    if (this._isDynamicallyLoadedComponent(token)) {
      return this._dynamicallyCreatedComponent;
    }
    return this._getByKey(Key.get(token), self, false, null);
  }
  _isDynamicallyLoadedComponent(token) {
    return isPresent(this._dynamicallyCreatedComponentBinding) &&
        identical(Key.get(token), this._dynamicallyCreatedComponentBinding.key);
  }
  bool hasDirective(Type type) {
    return !identical(
        this._getObjByKeyId(Key.get(type).id, LIGHT_DOM_AND_SHADOW_DOM),
        _undefined);
  }
  getEventEmitterAccessors() {
    return this._proto.eventEmitterAccessors;
  }
  getHostActionAccessors() {
    return this._proto.hostActionAccessors;
  }
  getComponent() {
    return this._obj0;
  }
  getElementRef() {
    return new ElementRef(
        new ViewRef(this._preBuiltObjects.view), this._proto.index);
  }
  getViewContainerRef() {
    return new ViewContainerRef(
        this._preBuiltObjects.viewManager, this.getElementRef());
  }
  getDynamicallyLoadedComponent() {
    return this._dynamicallyCreatedComponent;
  }
  ElementInjector directParent() {
    return this._proto.distanceToParent < 2 ? this.parent : null;
  }
  _isComponentKey(Key key) {
    return this._proto._firstBindingIsComponent &&
        identical(key.id, this._proto._keyId0);
  }
  _isDynamicallyLoadedComponentKey(Key key) {
    return isPresent(this._dynamicallyCreatedComponentBinding) &&
        identical(key.id, this._dynamicallyCreatedComponentBinding.key.id);
  }
  _new(ResolvedBinding binding) {
    if (this._constructionCounter++ > _MAX_DIRECTIVE_CONSTRUCTION_COUNTER) {
      throw new CyclicDependencyError(binding.key);
    }
    var factory = binding.factory;
    var deps = (binding.dependencies as List<DirectiveDependency>);
    var length = deps.length;
    var d0, d1, d2, d3, d4, d5, d6, d7, d8, d9;
    try {
      d0 = length > 0 ? this._getByDependency(deps[0], binding.key) : null;
      d1 = length > 1 ? this._getByDependency(deps[1], binding.key) : null;
      d2 = length > 2 ? this._getByDependency(deps[2], binding.key) : null;
      d3 = length > 3 ? this._getByDependency(deps[3], binding.key) : null;
      d4 = length > 4 ? this._getByDependency(deps[4], binding.key) : null;
      d5 = length > 5 ? this._getByDependency(deps[5], binding.key) : null;
      d6 = length > 6 ? this._getByDependency(deps[6], binding.key) : null;
      d7 = length > 7 ? this._getByDependency(deps[7], binding.key) : null;
      d8 = length > 8 ? this._getByDependency(deps[8], binding.key) : null;
      d9 = length > 9 ? this._getByDependency(deps[9], binding.key) : null;
    } catch (e, e_stack) {
      if (e is AbstractBindingError) e.addKey(binding.key);
      rethrow;
    }
    var obj;
    switch (length) {
      case 0:
        obj = factory();
        break;
      case 1:
        obj = factory(d0);
        break;
      case 2:
        obj = factory(d0, d1);
        break;
      case 3:
        obj = factory(d0, d1, d2);
        break;
      case 4:
        obj = factory(d0, d1, d2, d3);
        break;
      case 5:
        obj = factory(d0, d1, d2, d3, d4);
        break;
      case 6:
        obj = factory(d0, d1, d2, d3, d4, d5);
        break;
      case 7:
        obj = factory(d0, d1, d2, d3, d4, d5, d6);
        break;
      case 8:
        obj = factory(d0, d1, d2, d3, d4, d5, d6, d7);
        break;
      case 9:
        obj = factory(d0, d1, d2, d3, d4, d5, d6, d7, d8);
        break;
      case 10:
        obj = factory(d0, d1, d2, d3, d4, d5, d6, d7, d8, d9);
        break;
      default:
        throw '''Directive ${ binding . key . token} can only have up to 10 dependencies.''';
    }
    this._addToQueries(obj, binding.key.token);
    return obj;
  }
  _getByDependency(Dependency dep, Key requestor) {
    if (!(dep is DirectiveDependency)) {
      return this._getByKey(dep.key, self, dep.optional, requestor);
    }
    var dirDep = (dep as DirectiveDependency);
    if (isPresent(dirDep.attributeName)) return this._buildAttribute(dirDep);
    if (isPresent(dirDep.queryDirective)) return this
        ._findQuery(dirDep.queryDirective).list;
    if (identical(dirDep.key.id, StaticKeys.instance().changeDetectorRefId)) {
      var componentView =
          this._preBuiltObjects.view.componentChildViews[this._proto.index];
      return componentView.changeDetector.ref;
    }
    if (identical(dirDep.key.id, StaticKeys.instance().elementRefId)) {
      return this.getElementRef();
    }
    if (identical(dirDep.key.id, StaticKeys.instance().viewContainerId)) {
      return this.getViewContainerRef();
    }
    if (identical(dirDep.key.id, StaticKeys.instance().protoViewId)) {
      if (isBlank(this._preBuiltObjects.protoView)) {
        if (dirDep.optional) {
          return null;
        }
        throw new NoBindingError(dirDep.key);
      }
      return new ProtoViewRef(this._preBuiltObjects.protoView);
    }
    return this._getByKey(
        dirDep.key, dirDep.visibility, dirDep.optional, requestor);
  }
  String _buildAttribute(dep) {
    var attributes = this._proto.attributes;
    if (isPresent(attributes) &&
        MapWrapper.contains(attributes, dep.attributeName)) {
      return MapWrapper.get(attributes, dep.attributeName);
    } else {
      return null;
    }
  }
  _buildQueriesForDeps(List<DirectiveDependency> deps) {
    for (var i = 0; i < deps.length; i++) {
      var dep = deps[i];
      if (isPresent(dep.queryDirective)) {
        this._createQueryRef(dep.queryDirective);
      }
    }
  }
  _createQueryRef(directive) {
    var queryList = new QueryList();
    if (isBlank(this._query0)) {
      this._query0 = new QueryRef(directive, queryList, this);
    } else if (isBlank(this._query1)) {
      this._query1 = new QueryRef(directive, queryList, this);
    } else if (isBlank(this._query2)) {
      this._query2 = new QueryRef(directive, queryList, this);
    } else throw new QueryError();
  }
  _addToQueries(obj, token) {
    if (isPresent(this._query0) && (identical(this._query0.directive, token))) {
      this._query0.list.add(obj);
    }
    if (isPresent(this._query1) && (identical(this._query1.directive, token))) {
      this._query1.list.add(obj);
    }
    if (isPresent(this._query2) && (identical(this._query2.directive, token))) {
      this._query2.list.add(obj);
    }
  }
  // TODO(rado): unify with _addParentQueries.
  _inheritQueries(ElementInjector parent) {
    if (isBlank(parent)) return;
    if (isPresent(parent._query0)) {
      this._query0 = parent._query0;
    }
    if (isPresent(parent._query1)) {
      this._query1 = parent._query1;
    }
    if (isPresent(parent._query2)) {
      this._query2 = parent._query2;
    }
  }
  _buildQueries() {
    if (isBlank(this._proto)) return;
    var p = this._proto;
    if (p._binding0 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding0.dependencies as List<DirectiveDependency>));
    }
    if (p._binding1 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding1.dependencies as List<DirectiveDependency>));
    }
    if (p._binding2 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding2.dependencies as List<DirectiveDependency>));
    }
    if (p._binding3 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding3.dependencies as List<DirectiveDependency>));
    }
    if (p._binding4 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding4.dependencies as List<DirectiveDependency>));
    }
    if (p._binding5 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding5.dependencies as List<DirectiveDependency>));
    }
    if (p._binding6 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding6.dependencies as List<DirectiveDependency>));
    }
    if (p._binding7 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding7.dependencies as List<DirectiveDependency>));
    }
    if (p._binding8 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding8.dependencies as List<DirectiveDependency>));
    }
    if (p._binding9 is DirectiveBinding) {
      this._buildQueriesForDeps(
          (p._binding9.dependencies as List<DirectiveDependency>));
    }
  }
  _findQuery(token) {
    if (isPresent(this._query0) && identical(this._query0.directive, token)) {
      return this._query0;
    }
    if (isPresent(this._query1) && identical(this._query1.directive, token)) {
      return this._query1;
    }
    if (isPresent(this._query2) && identical(this._query2.directive, token)) {
      return this._query2;
    }
    throw new BaseException('''Cannot find query for directive ${ token}.''');
  }
  link(ElementInjector parent) {
    parent.addChild(this);
    this._addParentQueries();
  }
  linkAfter(ElementInjector parent, ElementInjector prevSibling) {
    parent.addChildAfter(this, prevSibling);
    this._addParentQueries();
  }
  _addParentQueries() {
    if (isPresent(this.parent._query0)) {
      this._addQueryToTree(this.parent._query0);
      this.parent._query0.update();
    }
    if (isPresent(this.parent._query1)) {
      this._addQueryToTree(this.parent._query1);
      this.parent._query1.update();
    }
    if (isPresent(this.parent._query2)) {
      this._addQueryToTree(this.parent._query2);
      this.parent._query2.update();
    }
  }
  unlink() {
    var queriesToUpDate = [];
    if (isPresent(this.parent._query0)) {
      this._pruneQueryFromTree(this.parent._query0);
      ListWrapper.push(queriesToUpDate, this.parent._query0);
    }
    if (isPresent(this.parent._query1)) {
      this._pruneQueryFromTree(this.parent._query1);
      ListWrapper.push(queriesToUpDate, this.parent._query1);
    }
    if (isPresent(this.parent._query2)) {
      this._pruneQueryFromTree(this.parent._query2);
      ListWrapper.push(queriesToUpDate, this.parent._query2);
    }
    this.remove();
    ListWrapper.forEach(queriesToUpDate, (q) => q.update());
  }
  _pruneQueryFromTree(QueryRef query) {
    this._removeQueryRef(query);
    var child = this._head;
    while (isPresent(child)) {
      child._pruneQueryFromTree(query);
      child = child._next;
    }
  }
  _addQueryToTree(QueryRef query) {
    this._assignQueryRef(query);
    var child = this._head;
    while (isPresent(child)) {
      child._addQueryToTree(query);
      child = child._next;
    }
  }
  _assignQueryRef(QueryRef query) {
    if (isBlank(this._query0)) {
      this._query0 = query;
      return;
    } else if (isBlank(this._query1)) {
      this._query1 = query;
      return;
    } else if (isBlank(this._query2)) {
      this._query2 = query;
      return;
    }
    throw new QueryError();
  }
  _removeQueryRef(QueryRef query) {
    if (this._query0 == query) this._query0 = null;
    if (this._query1 == query) this._query1 = null;
    if (this._query2 == query) this._query2 = null;
  }
  _getByKey(Key key, Visibility visibility, bool optional, Key requestor) {
    var ei = this;
    var currentVisibility = LIGHT_DOM;
    var depth = visibility.depth;
    if (!visibility.shouldIncludeSelf()) {
      depth -= ei._proto.distanceToParent;
      if (isPresent(ei._parent)) {
        ei = ei._parent;
      } else {
        ei = ei._host;
        if (!visibility.crossComponentBoundaries) {
          currentVisibility = SHADOW_DOM;
        }
      }
    }
    while (ei != null && depth >= 0) {
      var preBuiltObj = ei._getPreBuiltObjectByKeyId(key.id);
      if (!identical(preBuiltObj, _undefined)) return preBuiltObj;
      var dir = ei._getObjByKeyId(key.id, currentVisibility);
      if (!identical(dir, _undefined)) return dir;
      depth -= ei._proto.distanceToParent;
      if (identical(currentVisibility, SHADOW_DOM)) break;
      if (isPresent(ei._parent)) {
        ei = ei._parent;
      } else {
        ei = ei._host;
        if (!visibility.crossComponentBoundaries) {
          currentVisibility = SHADOW_DOM;
        }
      }
    }
    if (isPresent(this._host) && this._host._isComponentKey(key)) {
      return this._host.getComponent();
    } else if (isPresent(this._host) &&
        this._host._isDynamicallyLoadedComponentKey(key)) {
      return this._host.getDynamicallyLoadedComponent();
    } else if (optional) {
      return this._appInjector(requestor).getOptional(key);
    } else {
      return this._appInjector(requestor).get(key);
    }
  }
  _appInjector(Key requestor) {
    if (isPresent(requestor) &&
        (this._isComponentKey(requestor) ||
            this._isDynamicallyLoadedComponentKey(requestor))) {
      return this._shadowDomAppInjector;
    } else {
      return this._lightDomAppInjector;
    }
  }
  _getPreBuiltObjectByKeyId(int keyId) {
    var staticKeys = StaticKeys.instance();
    if (identical(keyId,
        staticKeys.viewManagerId)) return this._preBuiltObjects.viewManager;
    // TODO add other objects as needed
    return _undefined;
  }
  _getObjByKeyId(int keyId, num visibility) {
    var p = this._proto;
    if (identical(p._keyId0, keyId) && (p._visibility0 & visibility) > 0) {
      if (isBlank(this._obj0)) {
        this._obj0 = this._new(p._binding0);
      }
      return this._obj0;
    }
    if (identical(p._keyId1, keyId) && (p._visibility1 & visibility) > 0) {
      if (isBlank(this._obj1)) {
        this._obj1 = this._new(p._binding1);
      }
      return this._obj1;
    }
    if (identical(p._keyId2, keyId) && (p._visibility2 & visibility) > 0) {
      if (isBlank(this._obj2)) {
        this._obj2 = this._new(p._binding2);
      }
      return this._obj2;
    }
    if (identical(p._keyId3, keyId) && (p._visibility3 & visibility) > 0) {
      if (isBlank(this._obj3)) {
        this._obj3 = this._new(p._binding3);
      }
      return this._obj3;
    }
    if (identical(p._keyId4, keyId) && (p._visibility4 & visibility) > 0) {
      if (isBlank(this._obj4)) {
        this._obj4 = this._new(p._binding4);
      }
      return this._obj4;
    }
    if (identical(p._keyId5, keyId) && (p._visibility5 & visibility) > 0) {
      if (isBlank(this._obj5)) {
        this._obj5 = this._new(p._binding5);
      }
      return this._obj5;
    }
    if (identical(p._keyId6, keyId) && (p._visibility6 & visibility) > 0) {
      if (isBlank(this._obj6)) {
        this._obj6 = this._new(p._binding6);
      }
      return this._obj6;
    }
    if (identical(p._keyId7, keyId) && (p._visibility7 & visibility) > 0) {
      if (isBlank(this._obj7)) {
        this._obj7 = this._new(p._binding7);
      }
      return this._obj7;
    }
    if (identical(p._keyId8, keyId) && (p._visibility8 & visibility) > 0) {
      if (isBlank(this._obj8)) {
        this._obj8 = this._new(p._binding8);
      }
      return this._obj8;
    }
    if (identical(p._keyId9, keyId) && (p._visibility9 & visibility) > 0) {
      if (isBlank(this._obj9)) {
        this._obj9 = this._new(p._binding9);
      }
      return this._obj9;
    }
    return _undefined;
  }
  getDirectiveAtIndex(int index) {
    if (index == 0) return this._obj0;
    if (index == 1) return this._obj1;
    if (index == 2) return this._obj2;
    if (index == 3) return this._obj3;
    if (index == 4) return this._obj4;
    if (index == 5) return this._obj5;
    if (index == 6) return this._obj6;
    if (index == 7) return this._obj7;
    if (index == 8) return this._obj8;
    if (index == 9) return this._obj9;
    throw new OutOfBoundsAccess(index);
  }
  hasInstances() {
    return this._constructionCounter > 0;
  }
  /** Gets whether this element is exporting a component instance as $implicit. */
  isExportingComponent() {
    return this._proto.exportComponent;
  }
  /** Gets whether this element is exporting its element as $implicit. */
  isExportingElement() {
    return this._proto.exportElement;
  }
  /** Get the name to which this element's $implicit is to be assigned. */
  getExportImplicitName() {
    return this._proto.exportImplicitName;
  }
  getLightDomAppInjector() {
    return this._lightDomAppInjector;
  }
  getShadowDomAppInjector() {
    return this._shadowDomAppInjector;
  }
  getHost() {
    return this._host;
  }
  getBoundElementIndex() {
    return this._proto.index;
  }
}
class OutOfBoundsAccess extends BaseException {
  String message;
  OutOfBoundsAccess(index) : super() {
    /* super call moved to initializer */;
    this.message = '''Index ${ index} is out-of-bounds.''';
  }
  toString() {
    return this.message;
  }
}
class QueryError extends BaseException {
  String message;
  // TODO(rado): pass the names of the active directives.
  QueryError() : super() {
    /* super call moved to initializer */;
    this.message = "Only 3 queries can be concurrently active in a template.";
  }
  toString() {
    return this.message;
  }
}
class QueryRef {
  var directive;
  QueryList list;
  ElementInjector originator;
  QueryRef(directive, QueryList list, ElementInjector originator) {
    this.directive = directive;
    this.list = list;
    this.originator = originator;
  }
  update() {
    var aggregator = [];
    this.visit(this.originator, aggregator);
    this.list.reset(aggregator);
  }
  visit(ElementInjector inj, aggregator) {
    if (isBlank(inj)) return;
    if (inj.hasDirective(this.directive)) {
      ListWrapper.push(aggregator, inj.get(this.directive));
    }
    var child = inj._head;
    while (isPresent(child)) {
      this.visit(child, aggregator);
      child = child._next;
    }
  }
}
