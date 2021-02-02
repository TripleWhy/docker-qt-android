FROM ubuntu:20.04

ENV DEBIAN_FRONTEND noninteractive

ENV QT_VERSION           5.15.2
ENV QT_HOST              linux
ENV QT_TARGET            android
ENV QT_ARCH              ""
ENV QT_HOME              "/opt/Qt"
ENV QT_DIR               "${QT_HOME}/${QT_VERSION}/android"
ENV QT_BINDIR            "${QT_DIR}/bin"
ENV QT_QMAKE_EXECUTABLE  "${QT_BINDIR}/qmake"
ENV QT_ANDROIDDEPLOYPQT  "${QT_DIR}/bin/androiddeployqt"
ENV CMAKE_PREFIX_PATH    "${QT_DIR}"
ENV CMAKE_FIND_ROOT_PATH "${QT_DIR}"

ENV ANDROID_SDK_VERSION         30
ENV ANDROID_NDK_VERSION         21.4.7075529
ENV ANDROID_BUILD_TOOLS_VERSION 30.0.3
ENV ANDROID_HOME                "/opt/android-sdk-linux"
ENV ANDROID_SDK_HOME            "${ANDROID_HOME}"
ENV ANDROID_SDK_ROOT            "${ANDROID_HOME}"
ENV ANDROID_SDK                 "${ANDROID_HOME}"
ENV ANDROID_NDK                 "${ANDROID_HOME}/ndk/${ANDROID_NDK_VERSION}"
ENV ANDROID_NDK_ROOT            "${ANDROID_NDK}"
ENV ANDROID_NDK_MAKE            "${ANDROID_NDK}/prebuilt/linux-x86_64/bin/make"

ENV PATH "${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin"
ENV PATH "${PATH}:${ANDROID_HOME}/cmdline-tools/tools/bin"
ENV PATH "${PATH}:${ANDROID_HOME}/tools/bin"
ENV PATH "${PATH}:${ANDROID_HOME}/build-tools/${ANDROID_BUILD_TOOLS_VERSION}"
ENV PATH "${PATH}:${ANDROID_HOME}/platform-tools"
ENV PATH "${PATH}:${ANDROID_HOME}/bin"

RUN apt-get update -yqq && \
    apt-get dist-upgrade -yqq && \
    apt-get install -y curl expect git openjdk-11-jdk wget unzip python3-pip ninja-build cmake && \
    apt-get autoremove && \
    apt-get clean

COPY tools /opt/tools
COPY licenses /opt/licenses

WORKDIR "${ANDROID_HOME}"
RUN groupadd android && useradd -d "${ANDROID_HOME}" -g android android
RUN "/opt/tools/entrypoint.sh" built-in

RUN ${ANDROID_HOME}/cmdline-tools/tools/bin/sdkmanager "cmdline-tools;latest"
RUN ${ANDROID_HOME}/cmdline-tools/tools/bin/sdkmanager "build-tools;${ANDROID_BUILD_TOOLS_VERSION}"
RUN ${ANDROID_HOME}/cmdline-tools/tools/bin/sdkmanager "platform-tools"
RUN ${ANDROID_HOME}/cmdline-tools/tools/bin/sdkmanager "platforms;android-${ANDROID_SDK_VERSION}"
RUN ${ANDROID_HOME}/cmdline-tools/tools/bin/sdkmanager "ndk;${ANDROID_NDK_VERSION}"

WORKDIR "${QT_DIR}"
RUN pip3 install aqtinstall
RUN python3 -m aqt install -O "${QT_HOME}" "${QT_VERSION}" "${QT_HOST}" "${QT_TARGET}"
RUN patch "${QT_DIR}/lib/cmake/Qt5Core/Qt5AndroidSupport.cmake" < "/opt/tools/qt/zipalign.patch"
RUN git clone --depth 1 "https://github.com/KDAB/android_openssl.git" "${ANDROID_HOME}/android_openssl"
ENV PATH "${PATH}:${QT_BINDIR}"


RUN mkdir "/opt/tools/qt/build-qmake" && \
    cd "/opt/tools/qt/build-qmake" && \
    "${QT_QMAKE_EXECUTABLE}" "/opt/tools/qt/dummyQmlProject/dummyQmlProject.pro" \
                             -spec android-clang \
                             CONFIG-=qml_debug \
                             CONFIG+=qtquickcompiler \
                             CONFIG-=separate_debug_info \
                             'ANDROID_ABIS=armeabi-v7a arm64-v8a x86 x86_64' && \
    "${ANDROID_NDK_MAKE}" -f "/opt/tools/qt/build-qmake/Makefile" qmake_all && \
    "${ANDROID_NDK_MAKE}" -j$(nproc) && \
    "${ANDROID_NDK_MAKE}" INSTALL_ROOT="/opt/tools/qt/build-qmake/android-build" install && \
    "${QT_ANDROIDDEPLOYPQT}" --input "/opt/tools/qt/build-qmake/android-dummyQmlProject-deployment-settings.json" \
                             --output "/opt/tools/qt/build-qmake/android-build" \
                             --android-platform android-${ANDROID_SDK_VERSION} \
                             --jdk /usr/lib/jvm/java-11-openjdk-amd64/ \
                             --verbose \
                             --gradle \
                             --aab \
                             --jarsigner \
                             --release && \
    cd .. && \
    rm -rf "/opt/tools/qt/build-qmake"

RUN mkdir "/opt/tools/qt/build-cmake" && \
    cd "/opt/tools/qt/build-cmake" && \
    cmake -S "/opt/tools/qt/dummyQmlProject" \
          -B "/opt/tools/qt/build-cmake" \
          -GNinja \
          -DCMAKE_BUILD_TYPE:String=Release \
          -DQT_QMAKE_EXECUTABLE:STRING="${QT_QMAKE_EXECUTABLE}" \
          -DCMAKE_PREFIX_PATH:STRING="${QT_DIR}" \
          -DCMAKE_C_COMPILER:STRING="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++" \
          -DCMAKE_CXX_COMPILER:STRING="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++" \
          -DANDROID_NATIVE_API_LEVEL:STRING=16 \
          -DANDROID_NDK:PATH="${ANDROID_NDK}" \
          -DCMAKE_TOOLCHAIN_FILE:PATH="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
          -DANDROID_ABIS:STRING="armeabi-v7a arm64-v8a x86 x86_64" \
          -DANDROID_STL:STRING=c++_shared \
          -DCMAKE_FIND_ROOT_PATH:PATH="${QT_DIR}" \
          -DANDROID_SDK:PATH="${ANDROID_SDK}" && \
    cmake --build . --target all && \
    "${QT_ANDROIDDEPLOYPQT}" --input "/opt/tools/qt/build-cmake/android_deployment_settings.json" \
                             --output "/opt/tools/qt/build-cmake/android-build" \
                             --android-platform android-${ANDROID_SDK_VERSION} \
                             --jdk /usr/lib/jvm/java-11-openjdk-amd64/ \
                             --verbose \
                             --gradle \
                             --aab \
                             --jarsigner \
                             --release && \
    cd .. && \
    rm -rf "/opt/tools/qt/build-cmake"

WORKDIR "/root"
RUN rm -rf /opt/tools/qt
