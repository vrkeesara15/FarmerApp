package `in`.farmerapp.mitra

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * SEC-024 Play Integrity (standard requests) for `PlayIntegrityAttestation`
 * in farmerapp_core: `requestToken {cloudProjectNumber, requestHash}` answers
 * the integrity token or an error code; the Dart side then sends
 * `X-Integrity-Status: unavailable` and never blocks the user.
 */
class MainActivity : FlutterActivity() {
    private var provider: StandardIntegrityTokenProvider? = null
    private var providerProject = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "farmerapp/integrity")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestToken") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val project = call.argument<Number>("cloudProjectNumber")?.toLong() ?: 0L
                val hash = call.argument<String>("requestHash").orEmpty()
                if (project <= 0L || hash.isEmpty()) {
                    result.error("NOT_CONFIGURED", null, null)
                    return@setMethodCallHandler
                }
                withProvider(project, { ready ->
                    ready.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                        .addOnSuccessListener { response -> result.success(response.token()) }
                        .addOnFailureListener { e ->
                            provider = null // Expired providers are prepared again next time.
                            result.error(e.javaClass.simpleName, e.message, null)
                        }
                }, { e -> result.error(e.javaClass.simpleName, e.message, null) })
            }
    }

    private fun withProvider(
        project: Long,
        onReady: (StandardIntegrityTokenProvider) -> Unit,
        onError: (Exception) -> Unit,
    ) {
        val cached = provider
        if (cached != null && providerProject == project) {
            onReady(cached)
            return
        }
        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build(),
            )
            .addOnSuccessListener { ready ->
                provider = ready
                providerProject = project
                onReady(ready)
            }
            .addOnFailureListener(onError)
    }
}
