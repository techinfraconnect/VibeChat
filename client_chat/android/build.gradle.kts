allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val rootProjectBuildDir = rootProject.layout.buildDirectory.dir("../../build").get().asFile
subprojects {
    val newBuildDir = rootProject.layout.buildDirectory.dir("../../build/${project.name}").get().asFile
    project.layout.buildDirectory.set(newBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProjectBuildDir)
}