import 'package:angular2/core.dart';
import 'package:angular2/router.dart';

import '../app_header/app_header.dart';
import '../../services/firebase_service.dart';

@Component(
    selector: 'about'
)
@View(
    template: 'about',
)
class AboutCmp {}

@RouteConfig(const [const {
  'path': '/',
  'component': AppComponent
},
const {
  'path': '../about/',
  'component': AboutCmp,
  'as': 'about'
}
])

@Component(
    selector: 'my-app',
    templateUrl: 'app_component.html',
    directives: const [AppHeader],
    providers: const [FirebaseService],
    styleUrls: const ['app_component.css']
)
class AppComponent {
  final FirebaseService fbService;
  AppComponent(FirebaseService this.fbService);
  //TODO - setup a Router and use that to handle navigation
}
