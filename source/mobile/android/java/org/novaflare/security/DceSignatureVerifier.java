package org.novaflare.security;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;

import org.haxe.extension.Extension;

import java.security.MessageDigest;

/** Checks the Android signing certificate used by official D.C.E. builds. */
public final class DceSignatureVerifier
{
	private static final String PROJECT_CERT_SHA256 =
		"C60160598C765AE2702F36E706A6214360A897038B087375C6A6520EF181A867";

	private DceSignatureVerifier() {}

	public static boolean verifySignature()
	{
		try
		{
			PackageManager packageManager = Extension.mainContext.getPackageManager();
			String packageName = Extension.mainContext.getPackageName();
			Signature[] signatures;

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
			{
				PackageInfo packageInfo = packageManager.getPackageInfo(
					packageName, PackageManager.GET_SIGNING_CERTIFICATES);
				if (packageInfo.signingInfo == null)
					return false;
				signatures = packageInfo.signingInfo.hasMultipleSigners()
					? packageInfo.signingInfo.getApkContentsSigners()
					: packageInfo.signingInfo.getSigningCertificateHistory();
			}
			else
			{
				@SuppressWarnings("deprecation")
				PackageInfo packageInfo = packageManager.getPackageInfo(
					packageName, PackageManager.GET_SIGNATURES);
				signatures = packageInfo.signatures;
			}

			if (signatures == null)
				return false;

			MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
			for (Signature signature : signatures)
			{
				byte[] digest = sha256.digest(signature.toByteArray());
				StringBuilder fingerprint = new StringBuilder(digest.length * 2);
				for (byte value : digest)
					fingerprint.append(String.format("%02X", value & 0xFF));
				if (PROJECT_CERT_SHA256.equals(fingerprint.toString()))
					return true;
			}
			return false;
		}
		catch (Exception exception)
		{
			return false;
		}
	}
}
