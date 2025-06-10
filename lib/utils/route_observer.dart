//cspell:disable
import 'package:flutter/material.dart';

/// A custom route observer that notifies when a route is pushed or popped.
mixin RouteAwareStateMixin<T extends StatefulWidget> on State<T> implements RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      RouteObserverProvider.of(context).subscribe(this, route);
    }
  }

  @override
  void dispose() {
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      RouteObserverProvider.of(context).unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didPush() {
    // Route was pushed onto the navigator
  }

  @override
  void didPopNext() {
    // The top route has been popped off, and the current route shows up
  }
}

/// Provides access to the route observer
class RouteObserverProvider extends InheritedWidget {
  final RouteObserver<PageRoute> routeObserver;

  const RouteObserverProvider({
    Key? key,
    required this.routeObserver,
    required Widget child,
  }) : super(key: key, child: child);

  static RouteObserver<PageRoute> of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<RouteObserverProvider>();
    assert(provider != null, 'No RouteObserverProvider found in context');
    return provider!.routeObserver;
  }

  @override
  bool updateShouldNotify(RouteObserverProvider oldWidget) => false;
}

/// A widget that provides route observation to its descendants
class RouteObserverWrapper extends StatefulWidget {
  final Widget child;

  const RouteObserverWrapper({Key? key, required this.child}) : super(key: key);

  @override
  _RouteObserverWrapperState createState() => _RouteObserverWrapperState();
}

class _RouteObserverWrapperState extends State<RouteObserverWrapper> {
  final RouteObserver<PageRoute> _routeObserver = RouteObserver<PageRoute>();

  @override
  void dispose() {
    // No need to dispose RouteObserver as it's managed by Flutter
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RouteObserverProvider(
      routeObserver: _routeObserver,
      child: widget.child,
    );
  }
}
