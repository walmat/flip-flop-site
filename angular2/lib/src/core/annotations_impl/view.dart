library angular2.src.core.annotations_impl.view;

import "package:angular2/src/facade/lang.dart" show Type;

/**
 * Declares the available HTML templates for an application.
 *
 * Each angular component requires a single `@Component` and at least one `@View` annotation. The
 * @View
 * annotation specifies the HTML template to use, and lists the directives that are active within
 * the template.
 *
 * When a component is instantiated, the template is loaded into the component's shadow root, and
 * the
 * expressions and statements in the template are evaluated against the component.
 *
 * For details on the `@Component` annotation, see {@link Component}.
 *
 * ## Example
 *
 * ```
 * @Component({
 *   selector: 'greet'
 * })
 * @View({
 *   template: 'Hello {{name}}!',
 *   directives: [GreetUser, Bold]
 * })
 * class Greet {
 *   name: string;
 *
 *   constructor() {
 *     this.name = 'World';
 *   }
 * }
 * ```
 *
 * @exportedAs angular2/annotations
 */
class View {
  /**
   * Specifies a template URL for an angular component.
   *
   * NOTE: either `templateUrl` or `template` should be used, but not both.
   */
  final String templateUrl;
  /**
   * Specifies an inline template for an angular component.
   *
   * NOTE: either `templateUrl` or `template` should be used, but not both.
   */
  final String template;
  /**
   * Specifies a list of directives that can be used within a template.
   *
   * Directives must be listed explicitly to provide proper component encapsulation.
   *
   * ## Example
   *
   * ```javascript
   * @Component({
   *     selector: 'my-component'
   *   })
   * @View({
   *   directives: [For]
   *   template: '
   *   <ul>
   *     <li *ng-for="#item of items">{{item}}</li>
   *   </ul>'
   * })
   * class MyComponent {
   * }
   * ```
   */
  final List<Type> directives;
  /**
   * Specify a custom renderer for this View.
   * If this is set, neither `template`, `templateURL` nor `directives` are used.
   */
  final String renderer;
  const View({templateUrl, template, directives, renderer})
      : templateUrl = templateUrl,
        template = template,
        directives = directives,
        renderer = renderer;
}
