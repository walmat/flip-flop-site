library angular2.src.render.dom.shadow_dom.light_dom;

import "package:angular2/src/dom/dom_adapter.dart" show DOM;
import "package:angular2/src/facade/collection.dart" show List, ListWrapper;
import "package:angular2/src/facade/lang.dart" show isBlank, isPresent;
import "../view/view.dart" as viewModule;
import "content_tag.dart" show Content;

class DestinationLightDom {}
class _Root {
  var node;
  num boundElementIndex;
  _Root(node, boundElementIndex) {
    this.node = node;
    this.boundElementIndex = boundElementIndex;
  }
}
// TODO: LightDom should implement DestinationLightDom

// once interfaces are supported
class LightDom {
  // The light DOM of the element is enclosed inside the lightDomView
  viewModule.DomView lightDomView;
  // The shadow DOM
  viewModule.DomView shadowDomView;
  // The nodes of the light DOM
  List<dynamic> nodes;
  List<_Root> _roots;
  LightDom(viewModule.DomView lightDomView, element) {
    this.lightDomView = lightDomView;
    this.nodes = DOM.childNodesAsList(element);
    this._roots = null;
    this.shadowDomView = null;
  }
  attachShadowDomView(viewModule.DomView shadowDomView) {
    this.shadowDomView = shadowDomView;
  }
  detachShadowDomView() {
    this.shadowDomView = null;
  }
  redistribute() {
    redistributeNodes(this.contentTags(), this.expandedDomNodes());
  }
  List<Content> contentTags() {
    if (isPresent(this.shadowDomView)) {
      return this._collectAllContentTags(this.shadowDomView, []);
    } else {
      return [];
    }
  }
  // Collects the Content directives from the view and all its child views
  List<Content> _collectAllContentTags(
      viewModule.DomView view, List<Content> acc) {
    var contentTags = view.contentTags;
    var vcs = view.viewContainers;
    for (var i = 0; i < vcs.length; i++) {
      var vc = vcs[i];
      var contentTag = contentTags[i];
      if (isPresent(contentTag)) {
        ListWrapper.push(acc, contentTag);
      }
      if (isPresent(vc)) {
        ListWrapper.forEach(vc.contentTagContainers(), (view) {
          this._collectAllContentTags(view, acc);
        });
      }
    }
    return acc;
  }
  // Collects the nodes of the light DOM by merging:

  // - nodes from enclosed ViewContainers,

  // - nodes from enclosed content tags,

  // - plain DOM nodes
  List<dynamic> expandedDomNodes() {
    var res = [];
    var roots = this._findRoots();
    for (var i = 0; i < roots.length; ++i) {
      var root = roots[i];
      if (isPresent(root.boundElementIndex)) {
        var vc = this.lightDomView.viewContainers[root.boundElementIndex];
        var content = this.lightDomView.contentTags[root.boundElementIndex];
        if (isPresent(vc)) {
          res = ListWrapper.concat(res, vc.nodes());
        } else if (isPresent(content)) {
          res = ListWrapper.concat(res, content.nodes());
        } else {
          ListWrapper.push(res, root.node);
        }
      } else {
        ListWrapper.push(res, root.node);
      }
    }
    return res;
  }
  // Returns a list of Roots for all the nodes of the light DOM.

  // The Root object contains the DOM node and its corresponding boundElementIndex
  _findRoots() {
    if (isPresent(this._roots)) return this._roots;
    var boundElements = this.lightDomView.boundElements;
    this._roots = ListWrapper.map(this.nodes, (n) {
      var boundElementIndex = null;
      for (var i = 0; i < boundElements.length; i++) {
        var boundEl = boundElements[i];
        if (isPresent(boundEl) && identical(boundEl, n)) {
          boundElementIndex = i;
          break;
        }
      }
      return new _Root(n, boundElementIndex);
    });
    return this._roots;
  }
}
// Projects the light DOM into the shadow DOM
redistributeNodes(List<Content> contents, List<dynamic> nodes) {
  for (var i = 0; i < contents.length; ++i) {
    var content = contents[i];
    var select = content.select;
    // Empty selector is identical to <content/>
    if (identical(select.length, 0)) {
      content.insert(ListWrapper.clone(nodes));
      ListWrapper.clear(nodes);
    } else {
      var matchSelector = (n) => DOM.elementMatches(n, select);
      var matchingNodes = ListWrapper.filter(nodes, matchSelector);
      content.insert(matchingNodes);
      ListWrapper.removeAll(nodes, matchingNodes);
    }
  }
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i];
    if (isPresent(node.parentNode)) {
      DOM.remove(nodes[i]);
    }
  }
}
