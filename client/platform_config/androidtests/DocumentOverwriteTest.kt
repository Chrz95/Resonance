package org.resonance.resonance

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DocumentOverwriteTest {
    @Test fun verifiedOverwriteAndRecovery() {
        val root = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "overwrite-tests")
        try { check(DocumentOverwriteChecks.run(root) == 7) } finally { root.deleteRecursively() }
    }
}
