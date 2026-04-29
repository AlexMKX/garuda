"""Loopback-only HTTP readiness endpoint for sidecar operators.

Purpose
-------
Docker Compose healthchecks and ``docker compose up --wait`` need an
observable "ready" signal that flips only after the operator has
completed all bootstrap steps (e.g. NetworkManager.ensure_all). Without
this gate, downstream compose stacks that reference managed networks as
``external`` can race against operator startup.

Contract
--------
- Binds to 127.0.0.1 only. The operator container runs with
  ``network_mode: none``; binding to 0.0.0.0 would be meaningless and a
  latent footgun if the deployment posture ever changes.
- ``GET /health`` returns HTTP 503 with a "not ready" body until
  :meth:`mark_ready` is called once by the bootstrap path.
- ``GET /health`` returns HTTP 200 with a "ready" body thereafter.
- Any other path returns HTTP 404.
- :meth:`start` is idempotent; calling it twice does nothing the second
  time.
- :meth:`stop` releases the listening socket and joins the serving
  thread so the port is immediately reusable.

Implementation runs a Flask app under waitress in a daemon thread.
"""

from __future__ import annotations

import logging
import threading
from typing import Optional

from flask import Flask, Response
from waitress.server import create_server

logger = logging.getLogger(__name__)


class HealthServer:
    """Minimal readiness endpoint exposed on loopback."""

    def __init__(self, host: str = "127.0.0.1", port: int = 8080) -> None:
        self.host = host
        self.port = port
        self._ready = False
        self._server = None  # waitress server handle, set by start()
        self._thread: Optional[threading.Thread] = None
        self._app = self._build_app()

    def _build_app(self) -> Flask:
        app = Flask(__name__)

        @app.get("/health")
        def _health() -> Response:
            if self._ready:
                return Response(
                    "ready\n", status=200, mimetype="text/plain; charset=utf-8"
                )
            return Response(
                "not ready\n", status=503, mimetype="text/plain; charset=utf-8"
            )

        @app.errorhandler(404)
        def _nf(_exc) -> Response:
            return Response(
                "not found\n", status=404, mimetype="text/plain; charset=utf-8"
            )

        return app

    def start(self) -> None:
        """Start the background HTTP thread. Idempotent."""
        if self._server is not None:
            return
        server = create_server(self._app, host=self.host, port=self.port, threads=4)
        thread = threading.Thread(
            target=server.run,
            name="sidecar-operator-health",
            daemon=True,
        )
        thread.start()
        self._server = server
        self._thread = thread
        logger.info("health server listening on %s:%d", self.host, self.port)

    def mark_ready(self) -> None:
        """Flip the readiness flag to true."""
        if self._server is None:
            logger.warning("mark_ready called before start; ignoring")
            return
        self._ready = True
        logger.info("health server marked ready")

    def stop(self) -> None:
        """Shut the server down and release the listening socket."""
        if self._server is None:
            return
        try:
            self._server.close()
        finally:
            if self._thread is not None:
                self._thread.join(timeout=2.0)
            self._server = None
            self._thread = None
