"""
qq-connect-is-reconnect hook handler.

Hermes 0.17.0 merged the ``is_reconnect`` kwarg into
``gateway.run._connect_adapter_with_timeout`` but did not update
``gateway.platforms.qqbot.adapter.QQAdapter.connect`` to accept it. Every
watcher reconnect therefore fails with::

    TypeError: QQAdapter.connect() got an unexpected keyword argument
    'is_reconnect'

This hook rewrites ``QQAdapter.connect`` at gateway:startup so the kwarg
is silently absorbed. The reconnect watcher already ran for hours before
we installed this; once it is patched, the next reconnect cycle succeeds
and the QQ Bot platform joins the gateway normally.

Remove the hook after upstream lands the matching adapter signature.
"""

import functools
import logging

logger = logging.getLogger("hermes_hook.qq-connect-is-reconnect")


def _patch_qqbot_connect() -> bool:
    """Wrap QQAdapter.connect to accept and drop the is_reconnect kwarg.

    Returns True if the adapter was patched, False if the qqbot platform
    is not installed (no-op in that case so this hook stays portable).
    """
    try:
        from gateway.platforms.qqbot.adapter import QQAdapter
    except Exception as exc:  # pragma: no cover - qqbot missing on some installs
        logger.info("qqbot platform not importable, hook is a no-op: %s", exc)
        return False

    original = QQAdapter.connect

    # Idempotent: if a previous gateway start already wrapped it, skip.
    if getattr(original, "_hermes_is_reconnect_patched", False):
        logger.debug("QQAdapter.connect already patched, skipping")
        return True

    @functools.wraps(original)
    async def connect(self, *args, **kwargs):
        # Absorb the kwarg that upstream's run.py started forwarding but the
        # QQ adapter was never updated to accept. Drop it silently — the QQ
        # adapter does not implement stale-queue handling today, so passing
        # the hint through would do nothing useful anyway.
        kwargs.pop("is_reconnect", None)
        return await original(self, *args, **kwargs)

    connect._hermes_is_reconnect_patched = True  # type: ignore[attr-defined]
    QQAdapter.connect = connect
    logger.info("Patched QQAdapter.connect to accept is_reconnect kwarg")
    return True


def handle(event_type: str, context):  # noqa: D401 - hook signature required
    """gateway:startup hook entrypoint.

    Patches QQAdapter.connect before the reconnect watcher fires its
    first retry. context is unused but required by the hook contract.
    """
    if event_type != "gateway:startup":
        return
    _patch_qqbot_connect()