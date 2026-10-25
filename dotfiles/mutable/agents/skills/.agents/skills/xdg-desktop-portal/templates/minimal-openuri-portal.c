/*
 * Minimal OpenURI portal backend for xdg-desktop-portal.
 * Implements only org.freedesktop.portal.OpenURI — no OpenFile (fd_list) dependency.
 *
 * Compile (Guix):
 *   GLIB=$(find /gnu/store -maxdepth 1 -name "*-glib-2.86.0" | head -1)
 *   gcc -o openuri-portal minimal-openuri-portal.c \
 *     -I$GLIB/include/glib-2.0 -I$GLIB/lib/glib-2.0/include \
 *     -L$GLIB/lib -Wl,-rpath,$GLIB/lib \
 *     -lglib-2.0 -lgio-2.0 -lgobject-2.0 -O2
 *
 * Register:
 *   1. cp openuri-portal ~/.local/bin/
 *   2. Create ~/.local/share/xdg-desktop-portal/portals/openuri.portal
 *   3. Create ~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.openuri.service
 *   4. Update ~/.config/xdg-desktop-portal/portals.conf
 *   5. systemctl --user restart xdg-desktop-portal
 */

#include <gio/gio.h>
#include <string.h>
#include <stdlib.h>

#define PORTAL_DBUS_NAME "org.freedesktop.impl.portal.desktop.openuri"
#define PORTAL_OBJECT_PATH "/org/freedesktop/portal/desktop"

static GMainLoop *main_loop = NULL;

static void handle_method_call(GDBusConnection *connection,
                               const gchar *sender,
                               const gchar *object_path,
                               const gchar *interface_name,
                               const gchar *method_name,
                               GVariant *parameters,
                               GDBusMethodInvocation *invocation,
                               gpointer user_data)
{
    if (g_strcmp0(method_name, "OpenURI") == 0) {
        const gchar *parent_window;
        const gchar *uri;
        GVariant *options;

        g_variant_get(parameters, "(ss@a{sv})", &parent_window, &uri, &options);

        GError *error = NULL;
        gboolean ok = FALSE;

        if (g_str_has_prefix(uri, "file://")) {
            gchar *path = g_filename_from_uri(uri, NULL, NULL);
            if (path == NULL) path = g_strdup(uri + 7);

            GFile *file = g_file_new_for_path(path);
            GFileInfo *info = g_file_query_info(file,
                "standard::content-type,standard::fast-content-type",
                G_FILE_QUERY_INFO_NONE, NULL, NULL);

            if (info) {
                const gchar *content_type = g_file_info_get_content_type(info);
                if (content_type == NULL)
                    content_type = g_file_info_get_attribute_string(info,
                        "standard::fast-content-type");
                if (content_type == NULL)
                    content_type = "application/octet-stream";

                GAppInfo *appinfo = g_app_info_get_default_for_type(content_type, FALSE);
                if (appinfo) {
                    GList *files = NULL;
                    files = g_list_append(files, (gpointer)g_file_get_path(file));
                    ok = g_app_info_launch(appinfo, files, NULL, &error);
                    g_list_free(files);
                    g_object_unref(appinfo);
                } else {
                    g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
                        "No default app for type %s", content_type);
                }
                g_object_unref(info);
            } else {
                g_set_error(&error, G_IO_ERROR, G_IO_ERROR_FAILED,
                    "Cannot query file info for %s", path);
            }
            g_object_unref(file);
            g_free(path);
        } else {
            ok = g_app_info_launch_default_for_uri(uri, NULL, &error);
        }

        g_variant_unref(options);

        if (ok) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("()"));
        } else {
            g_dbus_method_invocation_return_error(invocation, G_IO_ERROR,
                G_IO_ERROR_FAILED, "Failed to open '%s': %s",
                uri, error ? error->message : "unknown error");
            if (error) g_error_free(error);
        }
        return;
    }

    if (g_strcmp0(method_name, "OpenFile") == 0) {
        gint32 fd_handle;
        GVariant *options;
        g_variant_get(parameters, "(h@a{sv})", &fd_handle, &options);
        g_variant_unref(options);
        g_dbus_method_invocation_return_error(invocation, G_IO_ERROR,
            G_IO_ERROR_NOT_SUPPORTED, "OpenFile not implemented in minimal backend");
        return;
    }

    g_dbus_method_invocation_return_error(invocation, G_IO_ERROR,
        G_IO_ERROR_NOT_SUPPORTED, "Unknown method: %s", method_name);
}

static const GDBusInterfaceVTable interface_vtable = {
    handle_method_call, NULL, NULL
};

static void on_bus_acquired(GDBusConnection *connection, const gchar *name, gpointer user_data)
{
    GDBusNodeInfo *introspection_data;
    static const gchar introspection_xml[] =
        "<node>"
        "  <interface name='org.freedesktop.portal.OpenURI'>"
        "    <method name='OpenURI'>"
        "      <arg type='s' name='parent_window' direction='in'/>"
        "      <arg type='s' name='uri' direction='in'/>"
        "      <arg type='a{sv}' name='options' direction='in'/>"
        "    </method>"
        "    <method name='OpenFile'>"
        "      <arg type='h' name='fd' direction='in'/>"
        "      <arg type='a{sv}' name='options' direction='in'/>"
        "    </method>"
        "  </interface>"
        "</node>";

    introspection_data = g_dbus_node_info_new_for_xml(introspection_xml, NULL);
    guint registration_id = g_dbus_connection_register_object(
        connection, PORTAL_OBJECT_PATH,
        introspection_data->interfaces[0],
        &interface_vtable, NULL, NULL, NULL);
    g_dbus_node_info_unref(introspection_data);

    if (registration_id == 0) {
        g_printerr("Failed to register object\n");
        g_main_loop_quit(main_loop);
    } else {
        g_print("OpenURI portal: registered object on %s\n", PORTAL_OBJECT_PATH);
    }
}

static void on_name_acquired(GDBusConnection *connection, const gchar *name, gpointer user_data) {
    g_print("OpenURI portal backend acquired name: %s\n", name);
}

static void on_name_lost(GDBusConnection *connection, const gchar *name, gpointer user_data) {
    g_printerr("Failed to acquire name: %s\n", name);
    g_main_loop_quit(main_loop);
}

int main(int argc, char *argv[])
{
    GError *error = NULL;
    GDBusConnection *connection = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (connection == NULL) {
        g_printerr("Failed to connect to session bus: %s\n", error->message);
        g_error_free(error);
        return 1;
    }

    guint owner_id = g_bus_own_name_on_connection(
        connection, PORTAL_DBUS_NAME,
        G_BUS_NAME_OWNER_FLAGS_REPLACE,
        on_bus_acquired, on_name_acquired, on_name_lost, NULL);

    main_loop = g_main_loop_new(NULL, FALSE);
    g_main_loop_run(main_loop);

    g_bus_unown_name(owner_id);
    g_object_unref(connection);
    g_main_loop_unref(main_loop);
    return 0;
}
