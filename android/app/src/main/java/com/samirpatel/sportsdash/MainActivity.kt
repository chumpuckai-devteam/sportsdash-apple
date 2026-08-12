package com.samirpatel.sportsdash

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.samirpatel.sportsdash.core.platform.DeviceProfile
import com.samirpatel.sportsdash.ui.SportsDashRoot
import com.samirpatel.sportsdash.ui.theme.SportsDashTheme
import com.samirpatel.sportsdash.ui.theme.VoidBlack

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val isTv = DeviceProfile.isTelevision(this)
        // Edge-to-edge is phone-first; TV keeps classic fullscreen chrome.
        if (!isTv) {
            enableEdgeToEdge()
        }
        setContent {
            SportsDashTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = VoidBlack) {
                    val vm: AppViewModel = viewModel(
                        factory = AppViewModel.factory(applicationContext),
                    )
                    SportsDashRoot(vm = vm, isTelevision = isTv)
                }
            }
        }
    }
}
