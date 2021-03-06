library angular2.src.core.annotations_impl.visibility;

import "package:angular2/src/di/annotations_impl.dart"
    show DependencyAnnotation;

class Visibility extends DependencyAnnotation {
  final num depth;
  final bool crossComponentBoundaries;
  const Visibility(this.depth, this.crossComponentBoundaries) : super();
  bool shouldIncludeSelf() {
    return identical(this.depth, 0);
  }
}
/**
 * Specifies that an injector should retrieve a dependency from its element.
 *
 * ## Example
 *
 * Here is a simple directive that retrieves a dependency from its element.
 *
 * ```
 * @Directive({
 *   selector: '[dependency]',
 *   properties: {
 *     'id':'dependency'
 *   }
 * })
 * class Dependency {
 *   id:string;
 * }
 *
 *
 * @Directive({
 *   selector: '[my-directive]'
 * })
 * class Dependency {
 *   constructor(@Self() dependency:Dependency) {
 *     expect(dependency.id).toEqual(1);
 *   };
 * }
 * ```
 *
 * We use this with the following HTML template:
 *
 * ```
 *<div dependency="1" my-directive></div>
 * ```
 *
 * @exportedAs angular2/annotations
 */
class Self extends Visibility {
  const Self() : super(0, false);
}
// make constants after switching to ts2dart
var self = new Self();
/**
 * Specifies that an injector should retrieve a dependency from the direct parent.
 *
 * ## Example
 *
 * Here is a simple directive that retrieves a dependency from its parent element.
 *
 * ```
 * @Directive({
 *   selector: '[dependency]',
 *   properties: {
 *     'id':'dependency'
 *   }
 * })
 * class Dependency {
 *   id:string;
 * }
 *
 *
 * @Directive({
 *   selector: '[my-directive]'
 * })
 * class Dependency {
 *   constructor(@Parent() dependency:Dependency) {
 *     expect(dependency.id).toEqual(1);
 *   };
 * }
 * ```
 *
 * We use this with the following HTML template:
 *
 * ```
 * <div dependency="1">
 *   <div dependency="2" my-directive></div>
 * </div>
 * ```
 * The `@Parent()` annotation in our constructor forces the injector to retrieve the dependency from
 * the
 * parent element (even thought the current element could resolve it): Angular injects
 * `dependency=1`.
 *
 * @exportedAs angular2/annotations
 */
class Parent extends Visibility {
  const Parent() : super(1, false);
}
/**
 * Specifies that an injector should retrieve a dependency from any ancestor element within the same
 * shadow boundary.
 *
 * An ancestor is any element between the parent element and shadow root.
 *
 *
 * ## Example
 *
 * Here is a simple directive that retrieves a dependency from an ancestor element.
 *
 * ```
 * @Directive({
 *   selector: '[dependency]',
 *   properties: {
 *     'id':'dependency'
 *   }
 * })
 * class Dependency {
 *   id:string;
 * }
 *
 *
 * @Directive({
 *   selector: '[my-directive]'
 * })
 * class Dependency {
 *   constructor(@Ancestor() dependency:Dependency) {
 *     expect(dependency.id).toEqual(2);
 *   };
 * }
 * ```
 *
 *  We use this with the following HTML template:
 *
 * ```
 * <div dependency="1">
 *   <div dependency="2">
 *     <div>
 *       <div dependency="3" my-directive></div>
 *     </div>
 *   </div>
 * </div>
 * ```
 *
 * The `@Ancestor()` annotation in our constructor forces the injector to retrieve the dependency
 * from the
 * nearest ancestor element:
 * - The current element `dependency="3"` is skipped because it is not an ancestor.
 * - Next parent has no directives `<div>`
 * - Next parent has the `Dependency` directive and so the dependency is satisfied.
 *
 * Angular injects `dependency=2`.
 *
 * @exportedAs angular2/annotations
 */
class Ancestor extends Visibility {
  const Ancestor() : super(999999, false);
}
/**
 * Specifies that an injector should retrieve a dependency from any ancestor element.
 *
 * An ancestor is any element between the parent element and shadow root.
 *
 *
 * ## Example
 *
 * Here is a simple directive that retrieves a dependency from an ancestor element.
 *
 * ```
 * @Directive({
 *   selector: '[dependency]',
 *   properties: {
 *     'id':'dependency'
 *   }
 * })
 * class Dependency {
 *   id:string;
 * }
 *
 *
 * @Directive({
 *   selector: '[my-directive]'
 * })
 * class Dependency {
 *   constructor(@Unbounded() dependency:Dependency) {
 *     expect(dependency.id).toEqual(2);
 *   };
 * }
 * ```
 *
 * @exportedAs angular2/annotations
 */
class Unbounded extends Visibility {
  const Unbounded() : super(999999, true);
}
